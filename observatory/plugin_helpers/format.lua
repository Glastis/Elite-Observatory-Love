local helpers = {}

local INT_PATTERN = "^(%-?)(%d+)$"
local LEADING_SPACES_PATTERN = "^%s+"
local THOUSAND_GROUP_PATTERN = "(%d%d%d)"
local THOUSAND_GROUP_REPLACEMENT = "%1 "
local INT_SUFFIX_PATTERN = "^(%-?%d+)(.*)$"
local TRAILING_WORD_PATTERN = "(%S+)%s*$"

function helpers.group_thousands(int_str)
    local sign, digits = int_str:match(INT_PATTERN)
    if not digits then return int_str end
    local grouped = digits:reverse():gsub(THOUSAND_GROUP_PATTERN, THOUSAND_GROUP_REPLACEMENT):reverse()
    return sign .. (grouped:gsub(LEADING_SPACES_PATTERN, ""))
end

function helpers.group_thousands_in_formatted(formatted)
    local int_part, rest = formatted:match(INT_SUFFIX_PATTERN)
    if not int_part then return formatted end
    return helpers.group_thousands(int_part) .. rest
end

function helpers.display_name(body, fallback)
    if body and body.name and body.name ~= "" and body.name ~= "?" then
        return body.name
    end
    return fallback
end

function helpers.strip_system_prefix(body_name, system_name)
    if not system_name or system_name == "" then return body_name end
    if body_name:sub(1, #system_name) ~= system_name then return body_name end
    local last_word = system_name:match(TRAILING_WORD_PATTERN)
    if not last_word then return body_name end
    local keep_from = #system_name - #last_word + 1
    local rest = body_name:sub(keep_from)
    if rest == "" then return body_name end
    return rest
end

local function value_above_threshold(value, threshold)
    return threshold and value >= threshold
end

function helpers.compact_number(value, scales, fallback)
    if not value or value <= 0 then return fallback end
    for _, scale in ipairs(scales) do
        if value_above_threshold(value, scale.threshold) then
            return string.format(scale.format, value / scale.divider)
        end
    end
    return tostring(value)
end

return helpers
