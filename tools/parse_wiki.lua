local USAGE_MESSAGE =
    "usage: love . --script tools/parse_wiki.lua <wiki_html_dir> [out_path]\n"
local DEFAULT_OUT_PATH = "plugins/bioinsights/codex/wiki_variants.lua"
local HEADLINE_PATTERN =
    '()<h2><span class="mw%-headline" id="([^"]+)">([^<]+)</span>'
local TABLE_CLASS_PATTERN = '<table class="fandom%-table"'
local TABLE_CLOSE_TAG = "</table>"
local TABLE_CLOSE_LEN = 8
local CONDITIONS_ANCHOR = 'id="Conditions_of_occurrence'
local LIST_OPEN_TAG = "<ul>"
local LIST_CLOSE_TAG = "</ul>"
local LIST_CLOSE_LEN = 5
local SHARED_VARIANT_ANCHOR = "Colored_variants"
local INDENT_STEP = "    "
local IDENTIFIER_PATTERN = "^[%a_][%w_]*$"

local METHOD_PATTERNS = {
    { pattern = "[Cc]olored variant determined by the parent star type",
      method = "star" },
    { pattern = "[Cc]olored variant determined by grade 4",
      method = "grade_4_material" },
    { pattern = "[Cc]olored variant determined by grade 3",
      method = "grade_3_material" },
    { pattern = "[Cc]olored variant determined by rare material",
      method = "rare_material" },
}

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

local function html_unescape(s)
    if not s then
        return s
    end
    s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
    s = s:gsub("&#160;", " "):gsub("&nbsp;", " "):gsub("&quot;", "\"")
    s = s:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
    return s
end

local function strip_tags(s)
    if not s then
        return s
    end
    s = s:gsub("<[^>]+>", "")
    s = html_unescape(s)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function build_section_index(html)
    local sections

    sections = {}
    for start_pos, anchor_id, header_text in html:gmatch(HEADLINE_PATTERN) do
        table.insert(sections, {
            anchor = anchor_id,
            header = strip_tags(header_text),
            start = start_pos,
        })
    end
    for i, sec in ipairs(sections) do
        sec.stop = (sections[i + 1] and sections[i + 1].start) or (#html + 1)
    end
    return sections
end

local function find_section(html, sec)
    return html:sub(sec.start, sec.stop - 1)
end

local function detect_variant_method(section_html)
    for _, entry in ipairs(METHOD_PATTERNS) do
        if section_html:find(entry.pattern) then
            return entry.method
        end
    end
    return nil
end

local function find_variants_table(section_html)
    local table_start
    local table_end

    table_start = section_html:find(TABLE_CLASS_PATTERN)
    if not table_start then
        return nil
    end
    table_end = section_html:find(TABLE_CLOSE_TAG, table_start, true)
    if not table_end then
        return nil
    end
    return section_html:sub(table_start, table_end + TABLE_CLOSE_LEN - 1)
end

local function parse_table_rows(table_html)
    local rows
    local cells

    rows = {}
    for _, tr_inner in table_html:gmatch("<tr[^>]*>()(.-)</tr>") do
        cells = {}
        for cell in tr_inner:gmatch("<t[hd][^>]*>(.-)</t[hd]>") do
            table.insert(cells, strip_tags(cell))
        end
        if #cells > 0 then
            table.insert(rows, cells)
        end
    end
    return rows
end

local function extract_conditions(section_html)
    local cond_start
    local list_start
    local list_end
    local list_html
    local conditions
    local text

    cond_start = section_html:find(CONDITIONS_ANCHOR, 1, true)
    if not cond_start then
        return {}
    end
    list_start = section_html:find(LIST_OPEN_TAG, cond_start, true)
    if not list_start then
        return {}
    end
    list_end = section_html:find(LIST_CLOSE_TAG, list_start, true)
    if not list_end then
        return {}
    end
    list_html = section_html:sub(list_start, list_end + LIST_CLOSE_LEN - 1)
    conditions = {}
    for li in list_html:gmatch("<li>(.-)</li>") do
        text = strip_tags(li)
        if text ~= "" then
            table.insert(conditions, text)
        end
    end
    return conditions
end

local function species_label_from_anchor(anchor)
    local parts
    local first

    parts = {}
    for word in anchor:gmatch("[^_]+") do
        first = word:sub(1, 1):upper() .. word:sub(2):lower()
        table.insert(parts, first)
    end
    return table.concat(parts, " ")
end

local function build_mapping_from_rows(rows)
    local mapping
    local key
    local value

    mapping = {}
    for i = 2, #rows do
        key = rows[i][1]
        value = rows[i][2]
        if key and value and key ~= "" and value ~= "" then
            mapping[key] = value
        end
    end
    return mapping
end

local function parse_species_section(section, section_html)
    local method
    local table_html
    local rows
    local headers
    local mapping

    method = detect_variant_method(section_html)
    table_html = find_variants_table(section_html)
    rows = table_html and parse_table_rows(table_html) or {}
    headers = rows[1] or {}
    mapping = build_mapping_from_rows(rows)
    return {
        species    = species_label_from_anchor(section.anchor),
        method     = method,
        headers    = headers,
        mapping    = mapping,
        conditions = extract_conditions(section_html),
    }
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

local function emit_array_lines(value, inner, indent, emit)
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
    ["nil"]     = function() return "nil" end,
    boolean     = function(value) return tostring(value) end,
    number      = function(value) return tostring(value) end,
    string      = function(value) return string.format("%q", value) end,
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
        lines = emit_array_lines(value, inner, indent, emit_lua_value)
    else
        lines = emit_map_lines(value, inner, emit_lua_value)
    end
    return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
end

local function find_shared_variant(sections, html)
    local section_html
    local method
    local table_html
    local rows
    local headers
    local mapping

    for _, sec in ipairs(sections) do
        if sec.anchor == SHARED_VARIANT_ANCHOR then
            section_html = find_section(html, sec)
            method = detect_variant_method(section_html)
            table_html = find_variants_table(section_html)
            rows = table_html and parse_table_rows(table_html) or {}
            headers = rows[1] or {}
            mapping = build_mapping_from_rows(rows)
            return method, headers, mapping
        end
    end
    return nil, {}, {}
end

local function resolve_entry_fields(entry, shared_method, shared_headers, shared_mapping)
    local method
    local headers
    local mapping

    method = entry.method or shared_method
    headers = (next(entry.mapping) and entry.headers) or shared_headers
    mapping = next(entry.mapping) and entry.mapping or shared_mapping
    return method, headers, mapping
end

local function process_genus_file(in_path)
    local html
    local sections
    local shared_method
    local shared_headers
    local shared_mapping
    local results
    local section_html
    local entry
    local method
    local headers
    local mapping

    html = read_file(in_path)
    if not html then
        return nil
    end
    sections = build_section_index(html)
    shared_method, shared_headers, shared_mapping = find_shared_variant(sections, html)
    results = {}
    for _, sec in ipairs(sections) do
        if sec.header:find(" ") then
            section_html = find_section(html, sec)
            entry = parse_species_section(sec, section_html)
            method, headers, mapping = resolve_entry_fields(entry,
                shared_method, shared_headers, shared_mapping)
            if method or #entry.conditions > 0 then
                results[entry.species] = {
                    variant_method  = method,
                    variant_headers = headers,
                    variant_mapping = mapping,
                    conditions      = entry.conditions,
                }
            end
        end
    end
    return results
end

local function collect_all_species(in_dir)
    local p
    local all
    local data

    p = io.popen("ls " .. in_dir .. "/*.html")
    if not p then
        print("ls failed")
        return nil
    end
    all = {}
    for line in p:lines() do
        data = process_genus_file(line)
        if data then
            for species, entry in pairs(data) do
                all[species] = entry
            end
        end
    end
    p:close()
    return all
end

local function count_entries(map)
    local count

    count = 0
    for _ in pairs(map) do
        count = count + 1
    end
    return count
end

local function main(args)
    local in_dir
    local out_path
    local all
    local count

    in_dir = args[1]
    out_path = args[2] or DEFAULT_OUT_PATH
    if not in_dir or in_dir == "" then
        io.stderr:write(USAGE_MESSAGE)
        os.exit(1)
    end
    all = collect_all_species(in_dir)
    if not all then
        return
    end
    count = count_entries(all)
    write_file(out_path, "return " .. emit_lua_value(all, "") .. "\n")
    print(string.format("parsed %d species -> %s", count, out_path))
end

main(arg or {})
