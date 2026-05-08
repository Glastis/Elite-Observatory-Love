-- Cross-platform path resolution for Elite Dangerous data files.
--
-- On Windows, journals live in:
--   %USERPROFILE%\Saved Games\Frontier Developments\Elite Dangerous
-- On Linux (Steam Proton), journals live inside the Wine prefix used by Steam
-- for app id 359320 (Elite Dangerous). Multiple installation flavours are
-- supported by walking a list of candidate paths.

local paths = {}

local SEP = package.config:sub(1, 1)
paths.SEP = SEP

-- Returns the running OS as a normalised string: "windows", "linux", "macos".
function paths.os()
    if love and love.system then
        local name = love.system.getOS()
        if name == "Windows" then return "windows"
        elseif name == "Linux" then return "linux"
        elseif name == "OS X" then return "macos"
        end
    end
    if SEP == "\\" then return "windows" end
    return "linux"
end

local function getenv(name)
    local v = os.getenv(name)
    if v == nil or v == "" then return nil end
    return v
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end
paths.exists = exists

-- Best-effort directory existence check using io.open; falls back to listing.
function paths.dir_exists(path)
    if path == nil or path == "" then return false end
    -- Try opening as a directory by appending a separator; on most platforms
    -- io.open on a directory returns nil, so we instead use os.rename trick.
    local ok, err = os.rename(path, path)
    if ok then return true end
    -- Some platforms (Windows) return permission errors for system folders.
    if err and err:lower():find("permission") then return true end
    return false
end

function paths.join(...)
    local parts = {...}
    local out = ""
    for i, p in ipairs(parts) do
        if p == nil or p == "" then
            -- skip
        elseif out == "" then
            out = p
        else
            local last = out:sub(-1)
            if last == "/" or last == "\\" then
                out = out .. p
            else
                out = out .. SEP .. p
            end
        end
    end
    return out
end

-- Returns user home directory, normalised to the host's separator.
function paths.home()
    local home = getenv("HOME") or getenv("USERPROFILE")
    if home then return home end
    if paths.os() == "windows" then
        local drive = getenv("HOMEDRIVE") or "C:"
        local path = getenv("HOMEPATH") or "\\"
        return drive .. path
    end
    return "/"
end

-- Returns the user's "Saved Games" folder on Windows.
function paths.saved_games_windows()
    local home = paths.home()
    return paths.join(home, "Saved Games")
end

-- Best-effort list of candidate Elite Dangerous journal folders, ordered by
-- likelihood. The first existing path wins. Returns a list of strings.
function paths.elite_dangerous_candidates()
    local candidates = {}
    local home = paths.home()
    local osname = paths.os()

    if osname == "windows" then
        table.insert(candidates,
            paths.join(paths.saved_games_windows(),
                "Frontier Developments", "Elite Dangerous"))
    elseif osname == "linux" then
        -- Steam Proton (Debian package layout used in original C# port)
        table.insert(candidates,
            paths.join(home,
                ".steam/debian-installation/steamapps/compatdata/359320/pfx/drive_c/users/steamuser/Saved Games/Frontier Developments/Elite Dangerous"))
        -- Steam Proton (standard layout)
        table.insert(candidates,
            paths.join(home,
                ".steam/steam/steamapps/compatdata/359320/pfx/drive_c/users/steamuser/Saved Games/Frontier Developments/Elite Dangerous"))
        -- Steam Proton (alternative ~/.local/share)
        table.insert(candidates,
            paths.join(home,
                ".local/share/Steam/steamapps/compatdata/359320/pfx/drive_c/users/steamuser/Saved Games/Frontier Developments/Elite Dangerous"))
        -- Flatpak Steam
        table.insert(candidates,
            paths.join(home,
                ".var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata/359320/pfx/drive_c/users/steamuser/Saved Games/Frontier Developments/Elite Dangerous"))
    elseif osname == "macos" then
        -- Crossover bottle (community ports)
        table.insert(candidates, paths.join(home,
            "Library/Application Support/CrossOver/Bottles/EliteDangerous/drive_c/users/crossover/Saved Games/Frontier Developments/Elite Dangerous"))
    end

    return candidates
end

-- Resolves the Elite Dangerous journal folder.
-- Optional `override` (string): user-configured path that wins if non-empty
-- and exists. Returns (path, source) where source is "override" / "auto" /
-- "fallback".
function paths.find_journal_folder(override)
    if override and override ~= "" and paths.dir_exists(override) then
        return override, "override"
    end
    for _, candidate in ipairs(paths.elite_dangerous_candidates()) do
        if paths.dir_exists(candidate) then
            return candidate, "auto"
        end
    end
    -- Fallback: return first candidate so the user has a sensible value to
    -- edit, even if it does not exist yet.
    local list = paths.elite_dangerous_candidates()
    return list[1] or paths.home(), "fallback"
end

-- Lists files in `dir` matching the Lua pattern `pattern` (full filename).
-- Uses io.popen with a platform-appropriate command. Returns a list of
-- absolute paths.
function paths.list_files(dir, pattern)
    if dir == nil or dir == "" then return {} end
    local files = {}
    local cmd
    if paths.os() == "windows" then
        -- /b => bare format, no headers
        cmd = string.format('cmd /c dir /b /a:-d "%s" 2>nul', dir)
    else
        -- ls -A to skip . and ..; -1 for one entry per line
        cmd = string.format('ls -A1 "%s" 2>/dev/null', dir:gsub('"', '\\"'))
    end
    local handle = io.popen(cmd)
    if not handle then return files end
    for name in handle:lines() do
        if name ~= "" then
            if pattern == nil or name:match(pattern) then
                table.insert(files, paths.join(dir, name))
            end
        end
    end
    handle:close()
    return files
end

-- Returns the file size in bytes, or nil if the file cannot be opened.
function paths.file_size(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return size
end

return paths
