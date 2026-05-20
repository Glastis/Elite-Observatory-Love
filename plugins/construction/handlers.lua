local state = require("plugins.construction.state")
local constants = require("plugins.construction.constants")
local journal_helpers = require("observatory.plugin_helpers.journal")

local handlers = {}

local DOLLAR_PREFIX_PATTERN = "^%$"
local NAME_SUFFIX_PATTERN = "_name;$"

local function normalize_commodity(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower():gsub(DOLLAR_PREFIX_PATTERN, "")
    return (key:gsub(NAME_SUFFIX_PATTERN, ""))
end

local function station_label(station_name, system_name)
    if not station_name then return nil end
    if system_name and system_name ~= "" then
        return station_name .. constants.SITE_LABEL_SEPARATOR .. system_name
    end
    return station_name
end

local function build_resources(resources_required)
    local list = {}
    if type(resources_required) ~= "table" then return list end
    for _, item in ipairs(resources_required) do
        local key = normalize_commodity(item.Name)
        if key then
            table.insert(list, {
                key      = key,
                display  = item.Name_Localised or item.Name or key,
                required = item.RequiredAmount or 0,
                provided = item.ProvidedAmount or 0,
                payment  = item.Payment or 0,
            })
        end
    end
    return list
end

local function resolved_station(market_id, existing)
    local known = state.station_for(market_id)
    if known and known.station then
        return known.station, known.system
    end
    if existing then
        return existing.station_name, existing.system_name
    end
    return nil, nil
end

local function on_position(entry)
    state.record_system_position(entry.StarSystem, entry.StarPos)
end

local function on_station_visit(entry)
    on_position(entry)
    if not entry.MarketID then return end
    state.record_station(tostring(entry.MarketID),
        entry.StationName, entry.StarSystem)
    if entry.Docked == false then
        state.clear_docked()
        return
    end
    state.set_docked(entry.StationName, entry.StarSystem)
end

local function on_undocked(_)
    state.clear_docked()
end

local function on_construction_depot(entry)
    if not entry.MarketID then return end
    local market_id = tostring(entry.MarketID)
    if entry.ConstructionComplete or entry.ConstructionFailed then
        state.remove_site(market_id)
        return
    end
    local station_name, system_name = resolved_station(market_id,
        state.get_site(market_id))
    state.upsert_site(market_id, {
        market_id     = market_id,
        station_name  = station_name,
        system_name   = system_name,
        system_coords = system_name and state.coords_for_system(system_name)
            or nil,
        label         = station_label(station_name, system_name)
            or (constants.UNKNOWN_SITE_PREFIX .. market_id),
        progress      = entry.ConstructionProgress,
        resources     = build_resources(entry.ResourcesRequired),
    })
end

local function on_cargo(entry)
    if entry.Vessel and entry.Vessel ~= constants.DEPOT_VESSEL then return end
    if type(entry.Inventory) ~= "table" then return end
    local cargo_by_key = {}
    for _, item in ipairs(entry.Inventory) do
        local key = normalize_commodity(item.Name)
        if key then
            cargo_by_key[key] = (cargo_by_key[key] or 0) + (item.Count or 0)
        end
    end
    state.set_cargo(cargo_by_key)
end

local DISPATCH_TABLE = {
    Docked                        = on_station_visit,
    Undocked                      = on_undocked,
    Location                      = on_station_visit,
    FSDJump                       = on_position,
    CarrierJump                   = on_station_visit,
    ColonisationConstructionDepot = on_construction_depot,
    Cargo                         = on_cargo,
    CargoFile                     = on_cargo,
}

handlers.dispatch = journal_helpers.create_dispatcher({
    handlers = DISPATCH_TABLE,
})

return handlers
