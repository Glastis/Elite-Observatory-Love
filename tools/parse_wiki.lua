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

local function html_unescape(s)
    if not s then return s end
    s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
    s = s:gsub("&#160;", " "):gsub("&nbsp;", " "):gsub("&quot;", "\"")
    s = s:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
    return s
end

local function strip_tags(s)
    if not s then return s end
    s = s:gsub("<[^>]+>", "")
    s = html_unescape(s)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function build_section_index(html)
    local sections = {}
    for start_pos, anchor_id, header_text in html:gmatch(
        '()<h2><span class="mw%-headline" id="([^"]+)">([^<]+)</span>') do
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

local function detect_variant_method(section_html)
    for _, entry in ipairs(METHOD_PATTERNS) do
        if section_html:find(entry.pattern) then
            return entry.method
        end
    end
    return nil
end

local function find_variants_table(section_html)
    local table_start = section_html:find('<table class="fandom%-table"')
    if not table_start then return nil end
    local table_end = section_html:find("</table>", table_start, true)
    if not table_end then return nil end
    return section_html:sub(table_start, table_end + 7)
end

local function parse_table_rows(table_html)
    local rows = {}
    for tr_open, tr_inner in table_html:gmatch("<tr[^>]*>()(.-)</tr>") do
        local cells = {}
        for cell in tr_inner:gmatch("<t[hd][^>]*>(.-)</t[hd]>") do
            table.insert(cells, strip_tags(cell))
        end
        if #cells > 0 then table.insert(rows, cells) end
    end
    return rows
end

local function extract_conditions(section_html)
    local cond_start = section_html:find('id="Conditions_of_occurrence', 1, true)
    if not cond_start then return {} end
    local list_start = section_html:find("<ul>", cond_start, true)
    if not list_start then return {} end
    local list_end = section_html:find("</ul>", list_start, true)
    if not list_end then return {} end
    local list_html = section_html:sub(list_start, list_end + 4)
    local conditions = {}
    for li in list_html:gmatch("<li>(.-)</li>") do
        local text = strip_tags(li)
        if text ~= "" then table.insert(conditions, text) end
    end
    return conditions
end

local function species_label_from_anchor(anchor)
    local parts = {}
    for word in anchor:gmatch("[^_]+") do
        local first = word:sub(1, 1):upper() .. word:sub(2):lower()
        table.insert(parts, first)
    end
    return table.concat(parts, " ")
end

local function parse_species_section(section, section_html, genus_default)
    local method = detect_variant_method(section_html)
    local table_html = find_variants_table(section_html)
    local rows = table_html and parse_table_rows(table_html) or {}
    local headers = rows[1] or {}
    local mapping = {}
    for i = 2, #rows do
        local key = rows[i][1]
        local value = rows[i][2]
        if key and value and key ~= "" and value ~= "" then
            mapping[key] = value
        end
    end
    return {
        species = species_label_from_anchor(section.anchor),
        method  = method,
        headers = headers,
        mapping = mapping,
        conditions = extract_conditions(section_html),
    }
end

local function emit_lua_value(value, indent)
    indent = indent or ""
    local t = type(value)
    if t == "nil" then return "nil" end
    if t == "boolean" then return tostring(value) end
    if t == "number" then return tostring(value) end
    if t == "string" then return string.format("%q", value) end
    if t == "table" then
        local is_array = true
        local count = 0
        for k in pairs(value) do
            count = count + 1
            if type(k) ~= "number" then is_array = false end
        end
        if count == 0 then return "{}" end
        local lines = {}
        local inner = indent .. "    "
        if is_array then
            for i = 1, #value do
                table.insert(lines, inner .. emit_lua_value(value[i], inner) .. ",")
            end
        else
            local keys = {}
            for k in pairs(value) do table.insert(keys, k) end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                local key_text
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    key_text = k
                else
                    key_text = "[" .. emit_lua_value(k, inner) .. "]"
                end
                table.insert(lines, inner .. key_text .. " = "
                    .. emit_lua_value(value[k], inner) .. ",")
            end
        end
        return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end

local function find_shared_variant(sections, html)
    for _, sec in ipairs(sections) do
        if sec.anchor == "Colored_variants" then
            local section_html = find_section(html, sec)
            local method = detect_variant_method(section_html)
            local table_html = find_variants_table(section_html)
            local rows = table_html and parse_table_rows(table_html) or {}
            local headers = rows[1] or {}
            local mapping = {}
            for i = 2, #rows do
                local key, value = rows[i][1], rows[i][2]
                if key and value and key ~= "" and value ~= "" then
                    mapping[key] = value
                end
            end
            return method, headers, mapping
        end
    end
    return nil, {}, {}
end

local function process_genus_file(in_path)
    local html = read_file(in_path)
    if not html then return nil end
    local sections = build_section_index(html)
    local shared_method, shared_headers, shared_mapping = find_shared_variant(sections, html)
    local results = {}
    for _, sec in ipairs(sections) do
        if sec.header:find(" ") then
            local section_html = find_section(html, sec)
            local entry = parse_species_section(sec, section_html, nil)
            local method = entry.method or shared_method
            local headers = (next(entry.mapping) and entry.headers) or shared_headers
            local mapping = next(entry.mapping) and entry.mapping or shared_mapping
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

local function main(args)
    local in_dir = args[1] or "../tmp_info_prediction"
    local out_path = args[2] or "plugins/bioinsights/codex/wiki_variants.lua"
    local p = io.popen("ls " .. in_dir .. "/*.html")
    if not p then print("ls failed") return end
    local all = {}
    for line in p:lines() do
        local data = process_genus_file(line)
        if data then
            for species, entry in pairs(data) do
                all[species] = entry
            end
        end
    end
    p:close()
    local count = 0
    for _ in pairs(all) do count = count + 1 end
    write_file(out_path, "return " .. emit_lua_value(all, "") .. "\n")
    print(string.format("parsed %d species -> %s", count, out_path))
end

main(arg or {})
