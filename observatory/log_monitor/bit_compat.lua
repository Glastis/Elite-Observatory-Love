local ok, native = pcall(require, "bit")
if ok then return native end

local fallback = {}

function fallback.bor(a, b)
    local r, p = 0, 1
    while a > 0 or b > 0 do
        local ab, bb = a % 2, b % 2
        if ab + bb > 0 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end

function fallback.band(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if (a % 2) == 1 and (b % 2) == 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end

function fallback.bnot(a)
    return (-1) - a
end

return fallback
