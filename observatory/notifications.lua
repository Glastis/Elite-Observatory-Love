-- Native popup notifications.
-- Equivalent of NativeNotification/NativePopup.cs. The original opens a
-- borderless top-most Win32 window per notification; in LÖVE we render
-- overlay panels in the corner of the main window. Each notification has a
-- timeout and auto-fades out.

local settings = require("observatory.settings")

local notifications = {}

local active = {}            -- list of notifications currently visible
local by_guid = {}           -- guid => notification
local next_id = 1

local function new_guid()
    next_id = next_id + 1
    return string.format("notif-%d-%d", os.time(), next_id)
end

local function corner_anchor()
    -- 0=TL, 1=TR, 2=BL, 3=BR
    local c = settings.get("NativeNotifyCorner") or 0
    if c == 0 then return "tl"
    elseif c == 1 then return "tr"
    elseif c == 2 then return "bl"
    elseif c == 3 then return "br"
    end
    return "tr"
end

-- args: { title, detail, timeout (ms, 0=persistent), guid, sender }
function notifications.send(args)
    args = args or {}
    if not settings.get("NativeNotify") then return nil end
    local timeout_ms = args.timeout
    if timeout_ms == nil or timeout_ms < 0 then
        timeout_ms = settings.get("NativeNotifyTimeout") or 8000
    end
    local guid = args.guid or new_guid()
    local notif = {
        guid = guid,
        title = args.title or "",
        detail = args.detail or "",
        timeout = timeout_ms / 1000, -- seconds; 0 = persistent
        born_at = love.timer and love.timer.getTime() or 0,
        sender = args.sender or "",
        fade = 1,
    }
    table.insert(active, notif)
    by_guid[guid] = notif
    return guid
end

function notifications.update(args)
    if not args or not args.guid then return end
    local n = by_guid[args.guid]
    if not n then return end
    n.title = args.title or n.title
    n.detail = args.detail or n.detail
    n.born_at = love.timer.getTime()
end

function notifications.cancel(guid)
    if not guid then return end
    by_guid[guid] = nil
    for i = #active, 1, -1 do
        if active[i].guid == guid then table.remove(active, i) end
    end
end

function notifications.tick(dt)
    local now = love.timer.getTime()
    for i = #active, 1, -1 do
        local n = active[i]
        if n.timeout > 0 then
            local age = now - n.born_at
            if age > n.timeout then
                table.remove(active, i)
                by_guid[n.guid] = nil
            elseif age > n.timeout - 0.5 then
                n.fade = math.max(0, (n.timeout - age) / 0.5)
            end
        end
    end
end

local function unpack_argb(argb)
    argb = argb or 0xFFFFA500
    local a = math.floor(argb / 0x1000000) % 256
    local r = math.floor(argb / 0x10000) % 256
    local g = math.floor(argb / 0x100) % 256
    local b = argb % 256
    return r / 255, g / 255, b / 255, a / 255
end

function notifications.draw()
    if #active == 0 then return end
    local anchor = corner_anchor()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local scale = (settings.get("NativeNotifyScale") or 100) / 100
    local pad = 12 * scale
    local width = 320 * scale
    local title_font = love.graphics.getFont()
    -- Stack notifications top-to-bottom from the chosen corner.
    local cursor_y
    if anchor == "tl" or anchor == "tr" then
        cursor_y = pad
    else
        cursor_y = sh - pad
    end

    for _, n in ipairs(active) do
        local lines_detail = {}
        for line in (n.detail .. "\n"):gmatch("(.-)\n") do
            table.insert(lines_detail, line)
        end
        local line_h = title_font:getHeight()
        local height = line_h * (1 + #lines_detail) + pad * 2

        local x
        if anchor == "tl" or anchor == "bl" then x = pad
        else x = sw - width - pad end

        local y
        if anchor == "tl" or anchor == "tr" then
            y = cursor_y
            cursor_y = cursor_y + height + pad
        else
            y = cursor_y - height
            cursor_y = cursor_y - height - pad
        end

        local r, g, b, a = unpack_argb(settings.get("NativeNotifyColour"))
        a = a * (n.fade or 1)

        love.graphics.setColor(0, 0, 0, 0.78 * (n.fade or 1))
        love.graphics.rectangle("fill", x, y, width, height, 6, 6)
        love.graphics.setColor(r, g, b, a)
        love.graphics.rectangle("line", x, y, width, height, 6, 6)

        love.graphics.setColor(r, g, b, a)
        love.graphics.printf(n.title, x + pad, y + pad, width - pad * 2, "left")
        love.graphics.setColor(1, 1, 1, n.fade or 1)
        local detail_y = y + pad + line_h
        for _, line in ipairs(lines_detail) do
            love.graphics.printf(line, x + pad, detail_y, width - pad * 2, "left")
            detail_y = detail_y + line_h
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function notifications.active()
    return active
end

return notifications
