local SORT_MODE_LABEL = {
    body  = "SORT BY BODY",
    price = "SORT BY PRICE",
}

local SYSTEM_TOGGLE_LABEL = {
    [true]  = "SHOW SYSTEM",
    [false] = "HIDE SYSTEM",
}

local SCANNED_TOGGLE_LABEL = {
    [true]  = "SHOW SCANNED",
    [false] = "HIDE SCANNED",
}

local PRIMARY_SORT_MODE  = "price"
local FALLBACK_SORT_MODE = "body"

local function system_toggle_label(plugin)
    return SYSTEM_TOGGLE_LABEL[plugin.is_system_hidden == true]
end

local function scanned_toggle_label(plugin)
    return SCANNED_TOGGLE_LABEL[plugin.is_scanned_hidden == true]
end

local function sort_mode_label(plugin)
    return SORT_MODE_LABEL[plugin.sort_mode]
        or SORT_MODE_LABEL[FALLBACK_SORT_MODE]
end

local function sort_mode_is_primary(plugin)
    return plugin.sort_mode == PRIMARY_SORT_MODE
end

return {
    sort_mode = {
        kind    = "cycle",
        label   = sort_mode_label,
        setter  = "cycle_sort_mode",
        primary = sort_mode_is_primary,
    },
    system_hidden = {
        label  = system_toggle_label,
        setter = "set_system_hidden",
        flag   = "is_system_hidden",
    },
    scanned_hidden = {
        label  = scanned_toggle_label,
        setter = "set_scanned_hidden",
        flag   = "is_scanned_hidden",
    },
}
