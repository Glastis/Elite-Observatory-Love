-- Elite Observatory (LÖVE port) — entry point.
-- Mirrors ObservatoryCore.cs: load settings, initialise the log monitor,
-- discover and load plugins, then hand off to the UI.

local settings        = require("observatory.settings")
local debug_mode      = require("observatory.debug_mode")
local log_monitor     = require("observatory.log_monitor")
local http_service    = require("observatory.http_service")
local plugin_manager  = require("observatory.plugin_manager")
local audio_handler   = require("observatory.audio_handler")
local core_form       = require("observatory.ui.core_form")
local ui_input        = require("observatory.ui.input")

function love.load(args)
    -- `--smoke [--journal PATH]` runs a non-graphical end-to-end check used by
    -- the test harness, then exits.
    local smoke = false
    local journal_override
    local run_tests = false
    local is_debug = false
    for i, a in ipairs(args or {}) do
        if a == "--smoke" then smoke = true
        elseif a == "--test" then run_tests = true
        elseif a == "--debug" then is_debug = true
        elseif a == "--journal" then journal_override = args[i + 1] end
    end
    debug_mode.set(is_debug)

    if run_tests then
        local loader = loadfile("tests/run.lua")
        if loader then loader() end
        love.event.quit(0)
        return
    end

    for i, a in ipairs(args or {}) do
        if a == "--script" and args[i + 1] then
            local script = args[i + 1]
            local rest = {}
            for j = i + 2, #args do table.insert(rest, args[j]) end
            local loader = loadfile(script)
            if not loader then
                print("could not load: " .. script)
                love.event.quit(1)
                return
            end
            arg = { [0] = script }
            for k, v in ipairs(rest) do arg[k] = v end
            local ok, err = pcall(loader, arg)
            if not ok then print("script error: " .. tostring(err)) end
            love.event.quit(0)
            return
        end
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
        for _, p in ipairs(plugin_manager.list()) do
            local rows = p.grid and p.grid.rows or {}
            print(string.format("  plugin %s: rows=%d", p.id, #rows))
        end
        love.event.quit(0)
        return
    end


    -- Linear filtering looks better on the mono labels than nearest.
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setFont(love.graphics.newFont(13))

    settings.load()

    log_monitor.init()
    http_service.start()
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
    plugin_manager.update(dt)
    audio_handler.update(dt)
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
    http_service.shutdown()
    log_monitor.shutdown()
    settings.save()
end
