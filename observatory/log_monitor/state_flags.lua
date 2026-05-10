local bit = require("observatory.log_monitor.bit_compat")

local state_flags = {}

state_flags.STATE = {
    Idle           = 0,
    Realtime       = 1,
    Batch          = 2,
    PreRead        = 4,
    BatchCancelled = 8,
}

function state_flags.has_flag(s, flag)
    return bit.band(s, flag) ~= 0
end

function state_flags.set_flag(s, flag)
    return bit.bor(s, flag)
end

function state_flags.clear_flag(s, flag)
    return bit.band(s, bit.bnot(flag))
end

function state_flags.is_batch_read(s)
    return state_flags.has_flag(s, state_flags.STATE.Batch)
        or state_flags.has_flag(s, state_flags.STATE.PreRead)
end

function state_flags.is_realtime(s)
    return state_flags.has_flag(s, state_flags.STATE.Realtime)
end

return state_flags
