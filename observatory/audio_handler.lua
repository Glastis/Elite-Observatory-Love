-- Audio playback wrapper around love.audio.
-- Original NAudio-based handler in C# manages a queue of WAV files; here we
-- mirror the queue semantics but rely on LÖVE's static Source playback.

local settings = require("observatory.settings")

local audio_handler = {}

local queue = {}
local current_source = nil
local current_options = nil

local function start_next()
    while #queue > 0 do
        local task = table.remove(queue, 1)
        local ok, src = pcall(love.audio.newSource, task.file_path, "static")
        if ok and src then
            local volume = settings.get("AudioVolume") or 0.75
            if task.options and task.options.volume then
                volume = volume * task.options.volume
            end
            src:setVolume(math.min(math.max(volume, 0), 1))
            src:play()
            current_source = src
            current_options = task.options or {}
            return
        end
    end
    current_source = nil
    current_options = nil
end

-- Enqueue and start playback when the queue is empty. Pass options.instant=true
-- to bypass the queue and play immediately, alongside other audio.
function audio_handler.play(file_path, options)
    if not file_path or file_path == "" then return end
    options = options or {}
    if options.instant then
        local ok, src = pcall(love.audio.newSource, file_path, "static")
        if ok and src then
            local volume = settings.get("AudioVolume") or 0.75
            if options.volume then volume = volume * options.volume end
            src:setVolume(math.min(math.max(volume, 0), 1))
            src:play()
        end
        return
    end
    table.insert(queue, { file_path = file_path, options = options })
    if not current_source then start_next() end
end

-- Tick from love.update so we can advance the queue when a source finishes.
function audio_handler.update(dt)
    if current_source and not current_source:isPlaying() then
        current_source = nil
        current_options = nil
        start_next()
    end
end

function audio_handler.is_playing()
    return current_source ~= nil
end

function audio_handler.clear()
    queue = {}
    if current_source then
        current_source:stop()
        current_source = nil
        current_options = nil
    end
end

return audio_handler
