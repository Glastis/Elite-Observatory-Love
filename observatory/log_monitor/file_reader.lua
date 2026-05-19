local paths = require("observatory.paths")

local file_reader = {}

local CRLF_TAIL = "\r"

local function strip_cr(line)
    if line:sub(-1) == CRLF_TAIL then return line:sub(1, -2) end
    return line
end

local function open_at(path, offset)
    local f = io.open(path, "rb")
    if not f then return nil end
    if offset > 0 then f:seek("set", offset) end
    return f
end

local function tail_content(path, prev_offset)
    local f = open_at(path, prev_offset)
    if not f then return nil end
    local chunk = f:read("*a") or ""
    f:close()
    return chunk
end

local function split_complete_lines(chunk, base_offset)
    local lines = {}
    local consumed_to = base_offset
    for line, lend in chunk:gmatch("([^\n]*)\n()") do
        line = strip_cr(line)
        if line ~= "" then table.insert(lines, line) end
        consumed_to = base_offset + (lend - 1)
    end
    return lines, consumed_to
end

local function adjust_offset_for_truncation(prev_offset, size)
    if size < prev_offset then return 0 end
    return prev_offset
end

function file_reader.read_new_lines(state, path)
    local size = paths.file_size(path)
    if size == nil then return {}, false end
    local prev_offset = adjust_offset_for_truncation(state.file_offsets[path] or 0, size)
    if size == prev_offset then
        state.file_sizes[path] = size
        return {}, false
    end
    local chunk = tail_content(path, prev_offset)
    if not chunk then return {}, false end
    local lines, consumed_to = split_complete_lines(chunk, prev_offset)
    state.file_offsets[path] = consumed_to
    state.file_sizes[path] = size
    return lines, true
end

function file_reader.read_all_lines(path)
    local f = io.open(path, "rb")
    if not f then return {}, 0 end
    local content = f:read("*a") or ""
    f:close()
    local lines = {}
    for line in content:gmatch("[^\n]+") do
        table.insert(lines, strip_cr(line))
    end
    return lines, #content
end

function file_reader.mark_consumed(state, path, size)
    local consumed = size or paths.file_size(path) or 0
    state.file_offsets[path] = consumed
    state.file_sizes[path] = consumed
end

return file_reader
