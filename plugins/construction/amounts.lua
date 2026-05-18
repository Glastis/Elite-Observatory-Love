local state = require("plugins.construction.state")

local amounts = {}

local FULLY_PROVIDED_FRACTION = 1

function amounts.for_resource(resource)
    local needed = math.max(0, (resource.required or 0) - (resource.provided or 0))
    local in_cargo = state.cargo_count(resource.key)
    local to_buy = math.max(0, needed - in_cargo)
    return needed, in_cargo, to_buy
end

function amounts.resource_fraction(resource)
    local required = resource.required or 0
    if required <= 0 then return FULLY_PROVIDED_FRACTION end
    return (resource.provided or 0) / required
end

function amounts.site_totals(site)
    local needed_total, cargo_total, to_buy_total = 0, 0, 0
    for _, resource in ipairs(site.resources or {}) do
        local needed, in_cargo, to_buy = amounts.for_resource(resource)
        needed_total = needed_total + needed
        if needed > 0 then
            cargo_total = cargo_total + in_cargo
            to_buy_total = to_buy_total + to_buy
        end
    end
    return needed_total, cargo_total, to_buy_total
end

local function compare_by_to_buy(a, b)
    return a.to_buy > b.to_buy
end

function amounts.unfinished(site)
    local list = {}
    for _, resource in ipairs((site or {}).resources or {}) do
        local needed, in_cargo, to_buy = amounts.for_resource(resource)
        if needed > 0 then
            table.insert(list, {
                resource = resource,
                needed   = needed,
                in_cargo = in_cargo,
                to_buy   = to_buy,
            })
        end
    end
    table.sort(list, compare_by_to_buy)
    return list
end

return amounts
