local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_file(path, content)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function trim_trailing_comma(s)
    return s:gsub(",%s*$", "")
end

local PYTHON_TO_LUA_LITERALS = {
    ["True"]  = "true",
    ["False"] = "false",
    ["None"]  = "nil",
}

local function strip_python_comments(line)
    return line:gsub("%s*#[^\n]*$", "")
end

local function literalize(value)
    value = trim(value)
    if PYTHON_TO_LUA_LITERALS[value] then
        return PYTHON_TO_LUA_LITERALS[value]
    end
    return value
end

local function convert_value(value, in_list)
    value = strip_python_comments(value)
    value = trim(value)
    if value == "" then return value end
    return literalize(value)
end

local function convert_dict_body(body)
    local result = {}
    local pos = 1
    local depth = 0
    local in_string = false
    local quote_char = nil
    local last_split = 1
    local segments = {}
    while pos <= #body do
        local c = body:sub(pos, pos)
        if in_string then
            if c == quote_char and body:sub(pos - 1, pos - 1) ~= "\\" then
                in_string = false
            end
        else
            if c == "'" or c == '"' then
                in_string = true
                quote_char = c
            elseif c == "{" or c == "[" or c == "(" then
                depth = depth + 1
            elseif c == "}" or c == "]" or c == ")" then
                depth = depth - 1
            elseif c == "," and depth == 0 then
                table.insert(segments, body:sub(last_split, pos - 1))
                last_split = pos + 1
            elseif c == "#" and depth == 0 and not in_string then
                local newline = body:find("\n", pos, true) or (#body + 1)
                body = body:sub(1, pos - 1) .. body:sub(newline)
                pos = pos - 1
            end
        end
        pos = pos + 1
    end
    table.insert(segments, body:sub(last_split))
    return segments
end

local function find_top_level(body, char)
    local pos = 1
    local depth = 0
    local in_string = false
    local quote_char
    while pos <= #body do
        local c = body:sub(pos, pos)
        if in_string then
            if c == quote_char and body:sub(pos - 1, pos - 1) ~= "\\" then
                in_string = false
            end
        else
            if c == "'" or c == '"' then
                in_string = true
                quote_char = c
            elseif c == "{" or c == "[" or c == "(" then
                depth = depth + 1
            elseif c == "}" or c == "]" or c == ")" then
                depth = depth - 1
            elseif c == char and depth == 0 then
                return pos
            end
        end
        pos = pos + 1
    end
    return nil
end

local function parse_python_value(text)
    text = trim(text)
    if text == "" then return nil end
    if text:sub(1, 1) == "'" or text:sub(1, 1) == '"' then
        return text:sub(2, -2)
    end
    if text == "True" then return true end
    if text == "False" then return false end
    if text == "None" then return nil end
    if text:sub(1, 1) == "[" then
        return parse_python_list(text:sub(2, -2))
    end
    if text:sub(1, 1) == "{" then
        return parse_python_dict(text:sub(2, -2))
    end
    local n = tonumber(text)
    if n then return n end
    return text
end

function parse_python_list(text)
    local result = {}
    local segments = convert_dict_body(text)
    for _, seg in ipairs(segments) do
        seg = trim(seg)
        if seg ~= "" then
            table.insert(result, parse_python_value(seg))
        end
    end
    return result
end

function parse_python_dict(text)
    local result = {}
    local segments = convert_dict_body(text)
    for _, seg in ipairs(segments) do
        seg = trim(seg)
        if seg ~= "" then
            local sep = find_top_level(seg, ":")
            if sep then
                local key = parse_python_value(seg:sub(1, sep - 1))
                local val = parse_python_value(seg:sub(sep + 1))
                result[key] = val
            end
        end
    end
    return result
end

local function emit_lua_value(v, indent)
    indent = indent or ""
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        local is_array = true
        local count = 0
        for k in pairs(v) do
            count = count + 1
            if type(k) ~= "number" then is_array = false end
        end
        if count == 0 then return "{}" end
        local lines = {}
        local inner_indent = indent .. "    "
        if is_array then
            for i = 1, #v do
                table.insert(lines, inner_indent .. emit_lua_value(v[i], inner_indent) .. ",")
            end
        else
            local keys = {}
            for k in pairs(v) do table.insert(keys, k) end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                local key_text
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    key_text = k
                else
                    key_text = "[" .. emit_lua_value(k, inner_indent) .. "]"
                end
                table.insert(lines, inner_indent .. key_text .. " = "
                    .. emit_lua_value(v[k], inner_indent) .. ",")
            end
        end
        return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end

local function extract_catalog_dict(source)
    local catalog_start = source:find("catalog%s*:?[^=]-=%s*{", 1)
    if not catalog_start then return nil end
    local brace_open = source:find("{", catalog_start, true)
    if not brace_open then return nil end
    local depth = 0
    local in_string = false
    local quote_char
    local pos = brace_open
    while pos <= #source do
        local c = source:sub(pos, pos)
        if in_string then
            if c == quote_char and source:sub(pos - 1, pos - 1) ~= "\\" then
                in_string = false
            end
        else
            if c == "'" or c == '"' then
                in_string = true
                quote_char = c
            elseif c == "{" then
                depth = depth + 1
            elseif c == "}" then
                depth = depth - 1
                if depth == 0 then
                    return source:sub(brace_open, pos)
                end
            end
        end
        pos = pos + 1
    end
    return nil
end

local function strip_comments(source)
    local lines = {}
    for line in source:gmatch("[^\n]*") do
        local stripped = line:gsub("%s*#[^\n]*$", "")
        table.insert(lines, stripped)
    end
    return table.concat(lines, "\n")
end

local function convert_file(in_path, out_path)
    local source = read_file(in_path)
    if not source then
        print("missing: " .. in_path)
        return false
    end
    source = strip_comments(source)
    local catalog_text = extract_catalog_dict(source)
    if not catalog_text then
        print("no catalog: " .. in_path)
        return false
    end
    local data = parse_python_value(catalog_text)
    local lua_text = "return " .. emit_lua_value(data, "") .. "\n"
    write_file(out_path, lua_text)
    print(string.format("converted %s -> %s",
        in_path:match("[^/]+$"), out_path:match("[^/]+$")))
    return true
end

local function main(args)
    local in_dir = args[1]
    local out_dir = args[2] or "plugins/bioinsights/codex"
    if not in_dir or in_dir == "" then
        io.stderr:write(
            "usage: love . --script tools/convert_rulesets.lua <ruleset_dir> [out_dir]\n")
        os.exit(1)
    end
    os.execute(string.format("mkdir -p %q", out_dir))
    local p = io.popen("ls " .. in_dir .. "/*.py")
    if not p then print("ls failed") return end
    for line in p:lines() do
        local base = line:match("([^/]+)%.py$")
        if base then
            convert_file(line, out_dir .. "/" .. base .. ".lua")
        end
    end
    p:close()
end

main(arg or {})
