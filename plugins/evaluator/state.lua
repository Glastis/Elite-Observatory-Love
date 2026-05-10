local store_helpers = require("observatory.plugin_helpers.state")

local function blank_body()
    return {
        name                  = "?",
        body_id               = nil,
        parent_body_id        = nil,
        body_type             = "",
        is_star               = false,
        is_landable           = false,
        terraformable         = false,
        distance_ls           = 0,
        gravity_ms2           = 0,
        mass_em               = 0,
        radius_m              = 0,
        volcanism             = "",
        atmosphere            = "",
        was_discovered        = false,
        was_mapped            = false,
        mapped_by_player      = false,
        was_footfalled        = false,
        current_value         = 0,
        potential_max         = 0,
        worth_mapping         = false,
        scanned               = false,
        notified_high_value   = false,
    }
end

local store = store_helpers.create_system_store(blank_body)

local state = {}

state.set_current_system       = store.set_current_system
state.current_system           = store.current_system
state.ensure_body              = store.ensure_body
state.bodies_in_current_system = store.bodies_in_current_system
state.systems_sorted           = store.systems_sorted
state.reset                    = store.reset

function state.current_system_address()
    return store.current_system_address
end

return state
