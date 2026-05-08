-- Example plugin: lists scanned bodies as the player explores.
-- Mirrors the kind of work ObservatoryExplorer does in C#: subscribes to
-- journal events, accumulates rows in its grid, sends a notification on
-- interesting finds.

local Plugin = {
    id = "example",
    name = "Example Explorer",
    short_name = "Explorer",
    version = "0.1.0",
    grid = {
        columns = { "Time", "Body", "Type", "Distance (Ls)" },
        column_align = { ["Distance (Ls)"] = "right" },
        rows = {},
    },
    default_settings = {
        notify_on_landable = true,
    },
}

local core_ref

function Plugin:load(core)
    core_ref = core
end

function Plugin:journal_event(entry)
    if not entry or not entry.event then return end
    if entry.event == "Scan" then
        local body = entry.BodyName or "?"
        local body_type = entry.PlanetClass or entry.StarType or entry.event
        local dls = entry.DistanceFromArrivalLS
        if type(dls) == "number" then dls = string.format("%.1f", dls)
        else dls = "" end
        table.insert(self.grid.rows, {
            ["Time"]          = entry.timestamp or "",
            ["Body"]          = body,
            ["Type"]          = body_type,
            ["Distance (Ls)"] = dls,
        })
        if self.settings and self.settings.notify_on_landable
            and entry.Landable == true and core_ref then
            core_ref:send_notification({
                title = "Landable Body",
                detail = string.format("%s (%s)", body, tostring(body_type)),
            })
        end
    elseif entry.event == "FSDJump" then
        if core_ref then
            core_ref:send_notification({
                title = "FSD Jump",
                detail = entry.StarSystem or "Unknown system",
            })
        end
    end
end

function Plugin:status_change(status)
    -- no-op; could surface fuel level, flags, etc.
end

return Plugin
