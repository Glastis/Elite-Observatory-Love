local route_distance = require("plugins.construction.route_distance")

local trips = {}

function trips.order(routes, depot_coords)
    table.sort(routes, function(a, b)
        local da
        local db

        da = route_distance.between(a.stops[1].station.coords, depot_coords) or 0
        db = route_distance.between(b.stops[1].station.coords, depot_coords) or 0
        return da < db
    end)
    return routes
end

function trips.add_all(routes, more)
    local index

    index = 1
    while more[index] do
        table.insert(routes, more[index])
        index = index + 1
    end
    return routes
end

return trips
