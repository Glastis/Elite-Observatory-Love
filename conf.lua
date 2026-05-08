-- LÖVE configuration. Loaded before main.lua.

function love.conf(t)
    t.identity = "EliteObservatoryLove"          -- save dir name
    t.appendidentity = false
    t.version = "11.4"

    t.window.title = "Elite Observatory"
    t.window.width = 1024
    t.window.height = 640
    t.window.minwidth = 720
    t.window.minheight = 480
    t.window.resizable = true
    t.window.vsync = 1

    t.modules.joystick = false
    t.modules.physics  = false
    t.modules.video    = false
    t.modules.touch    = false

    t.console = false
end
