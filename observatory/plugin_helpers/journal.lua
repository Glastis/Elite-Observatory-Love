local helpers = {}

local NULL_PARENT_KIND = "Null"

function helpers.for_each_parent(parents, fn)
    if type(parents) ~= "table" then return end
    for _, parent in ipairs(parents) do
        for kind, body_id in pairs(parent) do
            if kind ~= NULL_PARENT_KIND then fn(kind, body_id) end
        end
    end
end

function helpers.extract_parent_body_id(parents)
    local result
    helpers.for_each_parent(parents, function(_, body_id)
        if not result then result = body_id end
    end)
    return result
end

function helpers.extract_parent(parents)
    local result_id, result_kind
    helpers.for_each_parent(parents, function(kind, body_id)
        if not result_id then
            result_id = body_id
            result_kind = kind
        end
    end)
    return result_id, result_kind
end

function helpers.ensure_parent_chain(ensure_body_fn, system_address, parents)
    helpers.for_each_parent(parents, function(_, body_id)
        ensure_body_fn(system_address, body_id, nil)
    end)
end

function helpers.create_dispatcher(opts)
    local handlers = opts.handlers or {}
    local on_change = opts.on_change or function() end
    return function(entry, settings)
        if not entry or not entry.event then return end
        local handler = handlers[entry.event]
        if not handler then return end
        handler(entry, settings)
        on_change()
    end
end

return helpers
