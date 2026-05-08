local M = {}

local DEFAULT_INDENT_UNIT = "  "
local DEFAULT_BRANCH_GLYPH = "└─ "

function M.indent_prefix(depth, indent_unit, branch_glyph)
    if depth <= 0 then return "" end
    return string.rep(indent_unit or DEFAULT_INDENT_UNIT, depth - 1)
        .. (branch_glyph or DEFAULT_BRANCH_GLYPH)
end

local function expand_ancestors(displayed, parent_for)
    local frontier = {}
    for id in pairs(displayed) do table.insert(frontier, id) end
    while #frontier > 0 do
        local id = table.remove(frontier)
        local pid = parent_for(id)
        if pid ~= nil and not displayed[pid] then
            displayed[pid] = true
            table.insert(frontier, pid)
        end
    end
end

local function build_children(displayed, parent_for)
    local children = {}
    local roots = {}
    for id in pairs(displayed) do
        local pid = parent_for(id)
        if pid ~= nil and displayed[pid] then
            children[pid] = children[pid] or {}
            table.insert(children[pid], id)
        else
            table.insert(roots, id)
        end
    end
    return roots, children
end

local function noop_sort(_) end

function M.walk(spec)
    local displayed = {}
    for _, id in ipairs(spec.seed_ids or {}) do displayed[id] = true end
    expand_ancestors(displayed, spec.parent_for)
    local roots, children = build_children(displayed, spec.parent_for)
    local sort_ids = spec.sort_ids or noop_sort
    sort_ids(roots)
    for _, list in pairs(children) do sort_ids(list) end
    local visit = spec.visit
    local function dfs(id, depth)
        visit(id, depth)
        local kids = children[id]
        if not kids then return end
        for _, child in ipairs(kids) do dfs(child, depth + 1) end
    end
    for _, root in ipairs(roots) do dfs(root, 0) end
end

return M
