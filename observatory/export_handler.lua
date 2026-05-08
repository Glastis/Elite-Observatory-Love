-- Tab-separated export of a plugin's data grid.
-- Equivalent of Utils/ExportHandler.cs::ExportCSV. We omit the XLSX path: it
-- requires zipping a directory tree, which isn't practical from pure LÖVE.

local paths = require("observatory.paths")
local settings = require("observatory.settings")

local export_handler = {}

local function escape_field(value)
    if value == nil then return "" end
    local s = tostring(value)
    -- Strip tabs and newlines so we don't break a TSV row.
    s = s:gsub("\t", " "):gsub("\r?\n", " ")
    return s
end

-- plugin_grid is a table { columns = {"Col1","Col2",...}, rows = { {...}, ... } }
function export_handler.export_csv(plugin, plugin_grid, output_path)
    if not plugin_grid or not plugin_grid.columns then
        return false, "plugin has no grid to export"
    end
    local lines = {}
    table.insert(lines, table.concat(plugin_grid.columns, "\t"))
    for _, row in ipairs(plugin_grid.rows or {}) do
        local fields = {}
        for _, col in ipairs(plugin_grid.columns) do
            table.insert(fields, escape_field(row[col]))
        end
        table.insert(lines, table.concat(fields, "\t"))
    end
    local content = table.concat(lines, "\n") .. "\n"

    if not output_path or output_path == "" then
        local base = settings.get("ExportFolder")
        if not base or base == "" then base = paths.home() end
        local short = (plugin and (plugin.short_name or plugin.name)) or "plugin"
        local stamp = os.date("%Y-%m-%dT%H%M")
        output_path = paths.join(base,
            string.format("Export-%s-%s.csv", short, stamp))
    end

    local f, err = io.open(output_path, "wb")
    if not f then return false, err end
    f:write(content)
    f:close()
    return true, output_path
end

return export_handler
