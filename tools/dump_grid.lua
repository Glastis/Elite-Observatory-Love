local args = arg or {}
local journal_path = args[1]

if not journal_path or journal_path == "" then
    io.stderr:write("usage: love . --script tools/dump_grid.lua <journal_dir>\n")
    os.exit(1)
end

local settings        = require("observatory.settings")
local log_monitor     = require("observatory.log_monitor")
local plugin_manager  = require("observatory.plugin_manager")

settings.load()
settings.set("JournalFolder", journal_path)
log_monitor.init()
plugin_manager.load_all()
log_monitor.read_all({ blocking = true })

for _, p in ipairs(plugin_manager.list()) do
    print(string.format("=== plugin %s rows=%d ===", p.id,
        p.grid and #p.grid.rows or 0))
    if p.grid and p.grid.rows then
        local cols = p.grid.columns or {}
        for i, row in ipairs(p.grid.rows) do
            local parts = {}
            for _, col in ipairs(cols) do
                table.insert(parts, string.format("%s=%s", col,
                    tostring(row[col] or "")))
            end
            print(string.format("  [%d] %s", i, table.concat(parts, " | ")))
        end
    end
end
