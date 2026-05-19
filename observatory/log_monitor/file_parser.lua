local journal_reader = require("observatory.journal_reader")
local file_reader = require("observatory.log_monitor.file_reader")

local file_parser = {}

local function deserialize_lines(lines)
    local entries = {}
    local index = 1
    while index <= #lines do
        local is_ok, entry = pcall(journal_reader.deserialize, lines[index])
        if is_ok then
            entries[#entries + 1] = entry
        end
        index = index + 1
    end
    return entries
end

function file_parser.parse(index, path)
    local lines, size = file_reader.read_all_lines(path)
    return {
        index   = index,
        path    = path,
        size    = size,
        entries = deserialize_lines(lines),
    }
end

return file_parser
