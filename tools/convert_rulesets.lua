local USAGE_MESSAGE =
    "usage: love . --script tools/convert_rulesets.lua <ruleset_dir> [out_dir]\n"
local DEFAULT_OUT_DIR = "plugins/bioinsights/codex"
local INDENT_STEP = "    "
local IDENTIFIER_PATTERN = "^[%a_][%w_]*$"
local TRIM_PATTERN = "^%s*(.-)%s*$"
local PY_COMMENT_PATTERN = "%s*#[^\n]*$"
local CATALOG_HEADER_PATTERN = "catalog%s*:?[^=]-=%s*{"
local FILE_BASENAME_PATTERN = "[^/]+$"
local PY_BASENAME_PATTERN = "([^/]+)%.py$"

local QUOTE_CHARS = { ["'"] = true, ['"'] = true }
local OPEN_BRACKETS = { ["{"] = true, ["["] = true, ["("] = true }
local CLOSE_BRACKETS = { ["}"] = true, ["]"] = true, [")"] = true }

local function read_file(path)
    local f
    local data

    f = io.open(path, "rb")
    if not f then
        return nil
    end
    data = f:read("*a")
    f:close()
    return data
end

local function write_file(path, content)
    local f

    f = io.open(path, "wb")
    if not f then
        return false
    end
    f:write(content)
    f:close()
    return true
end

local function trim(s)
    return s:match(TRIM_PATTERN)
end

local function step_string_state(state, c, body, pos)
    if state.in_string then
        if c == state.quote_char and body:sub(pos - 1, pos - 1) ~= "\\" then
            state.in_string = false
        end
        return
    end
    if QUOTE_CHARS[c] then
        state.in_string = true
        state.quote_char = c
        return
    end
    if OPEN_BRACKETS[c] then
        state.depth = state.depth + 1
        return
    end
    if CLOSE_BRACKETS[c] then
        state.depth = state.depth - 1
    end
end

local function is_bracket_or_quote(c)
    return QUOTE_CHARS[c] or OPEN_BRACKETS[c] or CLOSE_BRACKETS[c]
end

local function dict_handle_quote_single(state)
    state.in_string = true
    state.quote_char = "'"
end

local function dict_handle_quote_double(state)
    state.in_string = true
    state.quote_char = '"'
end

local function dict_handle_open(state)
    state.depth = state.depth + 1
end

local function dict_handle_close(state)
    state.depth = state.depth - 1
end

local function dict_handle_comma(state)
    if state.depth ~= 0 then
        return
    end
    table.insert(state.segments, state.body:sub(state.last_split, state.pos - 1))
    state.last_split = state.pos + 1
end

local function dict_handle_hash(state)
    local newline

    if state.depth ~= 0 then
        return
    end
    newline = state.body:find("\n", state.pos, true) or (#state.body + 1)
    state.body = state.body:sub(1, state.pos - 1) .. state.body:sub(newline)
    state.pos = state.pos - 1
end

local DICT_DISPATCH = {
    ["'"] = dict_handle_quote_single,
    ['"'] = dict_handle_quote_double,
    ["{"] = dict_handle_open,
    ["["] = dict_handle_open,
    ["("] = dict_handle_open,
    ["}"] = dict_handle_close,
    ["]"] = dict_handle_close,
    [")"] = dict_handle_close,
    [","] = dict_handle_comma,
    ["#"] = dict_handle_hash,
}

local function step_dict_state(state)
    local c
    local handler

    c = state.body:sub(state.pos, state.pos)
    if state.in_string then
        if c == state.quote_char
            and state.body:sub(state.pos - 1, state.pos - 1) ~= "\\" then
            state.in_string = false
        end
        return
    end
    handler = DICT_DISPATCH[c]
    if handler then
        handler(state)
    end
end

local function convert_dict_body(body)
    local state

    state = {
        body       = body,
        pos        = 1,
        depth      = 0,
        in_string  = false,
        quote_char = nil,
        last_split = 1,
        segments   = {},
    }
    while state.pos <= #state.body do
        step_dict_state(state)
        state.pos = state.pos + 1
    end
    table.insert(state.segments, state.body:sub(state.last_split))
    return state.segments
end

local function find_top_level(body, char)
    local pos
    local state
    local c
    local is_state_change

    pos = 1
    state = { in_string = false, depth = 0, quote_char = nil }
    while pos <= #body do
        c = body:sub(pos, pos)
        is_state_change = state.in_string or is_bracket_or_quote(c)
        if is_state_change then
            step_string_state(state, c, body, pos)
        end
        if not is_state_change and c == char and state.depth == 0 then
            return pos
        end
        pos = pos + 1
    end
    return nil
end

local parse_python_value
local parse_python_list
local parse_python_dict

parse_python_value = function(text)
    local n

    text = trim(text)
    if text == "" then
        return nil
    end
    if text:sub(1, 1) == "'" or text:sub(1, 1) == '"' then
        return text:sub(2, -2)
    end
    if text == "True" then
        return true
    end
    if text == "False" then
        return false
    end
    if text == "None" then
        return nil
    end
    if text:sub(1, 1) == "[" then
        return parse_python_list(text:sub(2, -2))
    end
    if text:sub(1, 1) == "{" then
        return parse_python_dict(text:sub(2, -2))
    end
    n = tonumber(text)
    if n then
        return n
    end
    return text
end

parse_python_list = function(text)
    local result
    local segments

    result = {}
    segments = convert_dict_body(text)
    for _, seg in ipairs(segments) do
        seg = trim(seg)
        if seg ~= "" then
            table.insert(result, parse_python_value(seg))
        end
    end
    return result
end

parse_python_dict = function(text)
    local result
    local segments
    local sep
    local key
    local val

    result = {}
    segments = convert_dict_body(text)
    for _, seg in ipairs(segments) do
        seg = trim(seg)
        if seg ~= "" then
            sep = find_top_level(seg, ":")
            if sep then
                key = parse_python_value(seg:sub(1, sep - 1))
                val = parse_python_value(seg:sub(sep + 1))
                result[key] = val
            end
        end
    end
    return result
end

local function is_array_table(value)
    local count

    count = 0
    for k in pairs(value) do
        count = count + 1
        if type(k) ~= "number" then
            return false, count
        end
    end
    return true, count
end

local function emit_array_lines(value, inner, emit)
    local lines

    lines = {}
    for i = 1, #value do
        table.insert(lines, inner .. emit(value[i], inner) .. ",")
    end
    return lines
end

local function sorted_table_keys(value)
    local keys

    keys = {}
    for k in pairs(value) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function format_table_key(k, inner, emit)
    if type(k) == "string" and k:match(IDENTIFIER_PATTERN) then
        return k
    end
    return "[" .. emit(k, inner) .. "]"
end

local function emit_map_lines(value, inner, emit)
    local lines
    local keys
    local key_text

    lines = {}
    keys = sorted_table_keys(value)
    for _, k in ipairs(keys) do
        key_text = format_table_key(k, inner, emit)
        table.insert(lines, inner .. key_text .. " = "
            .. emit(value[k], inner) .. ",")
    end
    return lines
end

local SCALAR_EMITTERS = {
    ["nil"] = function() return "nil" end,
    boolean = function(v) return tostring(v) end,
    number  = function(v) return tostring(v) end,
    string  = function(v) return string.format("%q", v) end,
}

local function emit_lua_value(value, indent)
    local t
    local scalar
    local is_array
    local count
    local inner
    local lines

    indent = indent or ""
    t = type(value)
    scalar = SCALAR_EMITTERS[t]
    if scalar then
        return scalar(value)
    end
    if t ~= "table" then
        return "nil"
    end
    is_array, count = is_array_table(value)
    if count == 0 then
        return "{}"
    end
    inner = indent .. INDENT_STEP
    if is_array then
        lines = emit_array_lines(value, inner, emit_lua_value)
    else
        lines = emit_map_lines(value, inner, emit_lua_value)
    end
    return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
end

local function catalog_handle_quote_single(state)
    state.in_string = true
    state.quote_char = "'"
end

local function catalog_handle_quote_double(state)
    state.in_string = true
    state.quote_char = '"'
end

local function catalog_handle_open(state)
    state.depth = state.depth + 1
end

local function catalog_handle_close(state)
    state.depth = state.depth - 1
    if state.depth == 0 then
        state.is_done = true
    end
end

local CATALOG_DISPATCH = {
    ["'"] = catalog_handle_quote_single,
    ['"'] = catalog_handle_quote_double,
    ["{"] = catalog_handle_open,
    ["}"] = catalog_handle_close,
}

local function step_catalog_state(state, source)
    local c
    local handler

    c = source:sub(state.pos, state.pos)
    if state.in_string then
        if c == state.quote_char and source:sub(state.pos - 1, state.pos - 1) ~= "\\" then
            state.in_string = false
        end
        return
    end
    handler = CATALOG_DISPATCH[c]
    if handler then
        handler(state)
    end
end

local function extract_catalog_dict(source)
    local catalog_start
    local brace_open
    local state

    catalog_start = source:find(CATALOG_HEADER_PATTERN, 1)
    if not catalog_start then
        return nil
    end
    brace_open = source:find("{", catalog_start, true)
    if not brace_open then
        return nil
    end
    state = {
        pos        = brace_open,
        depth      = 0,
        in_string  = false,
        quote_char = nil,
        is_done    = false,
    }
    while state.pos <= #source do
        step_catalog_state(state, source)
        if state.is_done then
            return source:sub(brace_open, state.pos)
        end
        state.pos = state.pos + 1
    end
    return nil
end

local function strip_comments(source)
    local lines
    local stripped

    lines = {}
    for line in source:gmatch("[^\n]*") do
        stripped = line:gsub(PY_COMMENT_PATTERN, "")
        table.insert(lines, stripped)
    end
    return table.concat(lines, "\n")
end

local function convert_file(in_path, out_path)
    local source
    local catalog_text
    local data
    local lua_text

    source = read_file(in_path)
    if not source then
        print("missing: " .. in_path)
        return false
    end
    source = strip_comments(source)
    catalog_text = extract_catalog_dict(source)
    if not catalog_text then
        print("no catalog: " .. in_path)
        return false
    end
    data = parse_python_value(catalog_text)
    lua_text = "return " .. emit_lua_value(data, "") .. "\n"
    write_file(out_path, lua_text)
    print(string.format("converted %s -> %s",
        in_path:match(FILE_BASENAME_PATTERN), out_path:match(FILE_BASENAME_PATTERN)))
    return true
end

local function main(args)
    local in_dir
    local out_dir
    local p
    local base

    in_dir = args[1]
    out_dir = args[2] or DEFAULT_OUT_DIR
    if not in_dir or in_dir == "" then
        io.stderr:write(USAGE_MESSAGE)
        os.exit(1)
    end
    os.execute(string.format("mkdir -p %q", out_dir))
    p = io.popen("ls " .. in_dir .. "/*.py")
    if not p then
        print("ls failed")
        return
    end
    for line in p:lines() do
        base = line:match(PY_BASENAME_PATTERN)
        if base then
            convert_file(line, out_dir .. "/" .. base .. ".lua")
        end
    end
    p:close()
end

main(arg or {})
