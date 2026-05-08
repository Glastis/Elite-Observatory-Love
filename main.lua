-- Elite Observatory (LÖVE port) — entry point.
-- Mirrors ObservatoryCore.cs: load settings, initialise the log monitor,
-- discover and load plugins, then hand off to the UI.

local settings        = require("observatory.settings")
local log_monitor     = require("observatory.log_monitor")
local plugin_manager  = require("observatory.plugin_manager")
local notifications   = require("observatory.notifications")
local audio_handler   = require("observatory.audio_handler")
local core_form       = require("observatory.ui.core_form")
local ui_input        = require("observatory.ui.input")

function love.load(args)
    -- `--smoke [--journal PATH]` runs a non-graphical end-to-end check used by
    -- the test harness, then exits.
    local smoke = false
    local journal_override
    for i, a in ipairs(args or {}) do
        if a == "--smoke" then smoke = true
        elseif a == "--journal" then journal_override = args[i + 1] end
    end

    if smoke then
        settings.load()
        if journal_override then
            settings.set("JournalFolder", journal_override)
        end
        log_monitor.init()
        plugin_manager.load_all()
        log_monitor.read_all({ blocking = true })
        print(string.format("smoke ok: plugins=%d events=%d last=%s",
            #plugin_manager.list(),
            log_monitor.total_events(),
            log_monitor.last_event()))
        love.event.quit(0)
        return
    end

    -- Linear filtering looks better on the mono labels than nearest.
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setFont(love.graphics.newFont(13))

    settings.load()

    log_monitor.init()
    plugin_manager.load_all()

    if settings.get("StartReadAll") then
        log_monitor.read_all()
    end

    if settings.get("StartMonitor") then
        log_monitor.start()
    end

    plugin_manager.observatory_ready()
end

function love.update(dt)
    -- Open a fresh input frame so dt is available to every component during
    -- love.draw (animations advance in lockstep with input edges).
    ui_input.begin(dt)
    log_monitor.update(dt)
    audio_handler.update(dt)
    notifications.tick(dt)
end

function love.draw()
    core_form.draw()
    -- Snapshot button state for next-frame edge detection and flush wheel.
    ui_input.finish()
end

function love.wheelmoved(dx, dy)
    core_form.wheel(dx, dy)
end

function love.textinput(t)
    ui_input.feed_text(t)
end

function love.keypressed(key)
    -- When a text field has focus, route editing keys to it and skip global
    -- shortcuts so typing "escape" cancels the edit instead of quitting.
    if ui_input.has_focus() then
        ui_input.feed_key(key)
        return
    end
    if key == "f5" then
        plugin_manager.load_all()
        plugin_manager.observatory_ready()
    elseif key == "escape" then
        love.event.quit()
    end
end

function love.quit()
    settings.save()
end
