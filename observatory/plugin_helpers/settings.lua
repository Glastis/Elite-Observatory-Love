local helpers = {}

function helpers.apply_defaults(plugin)
    plugin.settings = plugin.settings or {}
    if type(plugin.default_settings) ~= "table" then return plugin.settings end
    for key, value in pairs(plugin.default_settings) do
        if plugin.settings[key] == nil then plugin.settings[key] = value end
    end
    return plugin.settings
end

return helpers
