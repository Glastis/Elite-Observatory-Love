# Elite Observatory (LÖVE port)

A Lua/[LÖVE](https://love2d.org/) port of [Elite Observatory Core](https://observatory.xjph.net/).
The original C# / Windows Forms application has been re-implemented in pure
Lua so it runs unchanged on Windows and Linux (LÖVE 11.x).

## Status

This is a working but **minimal** port. The following is implemented:

- Cross-platform detection of the Elite Dangerous journal folder
  - Windows: `%USERPROFILE%\Saved Games\Frontier Developments\Elite Dangerous`
  - Linux (Steam Proton, several common layouts)
  - Linux (Flatpak Steam)
  - macOS (CrossOver bottle, best effort)
- Live monitoring of the latest `Journal.*.log` and `Status.json` (polling)
- Pre-read of recent journals to establish current player context
- "Read All" batch processing of every journal in the folder
- Plugin system written in Lua (`plugins/<id>/init.lua` returning a table)
- Per-plugin grid UI, exportable to TSV (`.csv`)
- Native popup notifications rendered as overlay panels
- Audio playback of WAV/OGG via `love.audio`
- Settings persistence in the LÖVE save directory (`observatory.config`)
- Dark / Light themes

The following parts of the original C# project are intentionally **not**
ported and left as stubs / TODO:
- Loading binary `.eop` / `.dll` plugin packages (Lua plugins only)
- TTS / native voice notifications (no equivalent in LÖVE; could be wired
  to a system command if desired)
- XLSX export (the simpler TSV path is supported)
- Full themed-control registration system (themes apply globally)

## Running

You need [LÖVE 11.x](https://love2d.org/).

```sh
# Linux / macOS
love .
# Windows
"C:\Program Files\LOVE\love.exe" .
```

Press `F5` to reload plugins, `Esc` to quit.

A non-graphical end-to-end check is available for CI:

```sh
love . --smoke                          # uses the auto-detected journal folder
love . --smoke --journal /path/to/dir   # forces a specific journal folder
```

A pure-Lua unit-test suite covering `paths`, `journal_reader`, `export_handler`
and the `LogMonitorState` flags lives under `tests/`. Run it with any Lua 5.x
or LuaJIT — no LÖVE runtime needed:

```sh
lua tests/run.lua
```

## Writing a plugin

Plugins live under `plugins/<id>/init.lua` and return a table:

```lua
local Plugin = {
    id = "my-plugin",
    name = "My Plugin",
    short_name = "MP",
    version = "0.1.0",
    grid = { columns = { "Time", "Detail" }, rows = {} },
    default_settings = { my_option = true },
}

function Plugin:load(core)
    self.core = core
end

function Plugin:journal_event(entry)
    if entry.event == "FSDJump" then
        table.insert(self.grid.rows, {
            ["Time"]   = entry.timestamp,
            ["Detail"] = "Jumped to " .. (entry.StarSystem or "?"),
        })
        self.core:send_notification({ title = "Jump", detail = entry.StarSystem })
    end
end

function Plugin:status_change(status) end
function Plugin:on_notification(args) end

return Plugin
```

The core API is documented in [`observatory/core.lua`](observatory/core.lua).

## Project layout

```
main.lua              -- LÖVE entry point
conf.lua              -- LÖVE config (window size, modules)
lib/json.lua          -- rxi/json.lua (MIT)
observatory/
  paths.lua           -- OS detection and journal-folder lookup
  settings.lua        -- JSON-backed settings persistence
  journal_reader.lua  -- Per-line JSON deserialisation
  log_monitor.lua     -- Polling-based file watcher
  audio_handler.lua   -- Queued love.audio playback
  notifications.lua   -- Overlay popup notifications
  export_handler.lua  -- TSV export
  plugin_manager.lua  -- Discover and load Lua plugins
  core.lua            -- API surface passed to plugins (IObservatoryCore)
  ui/
    theme.lua
    widgets.lua       -- Minimal immediate-mode widgets
    core_form.lua     -- Main UI form
plugins/
  example/init.lua    -- Demonstration plugin
```

## Adapting paths

If your Elite Dangerous install is in an unusual location, edit the
`Journal Folder` in the Core Settings tab — it will be persisted to the
LÖVE save directory and used on subsequent launches. The list of paths
probed automatically lives in `observatory/paths.lua` under
`paths.elite_dangerous_candidates()`.

## License

- `lib/json.lua` is MIT (rxi/json.lua).
- This port follows the original ObservatoryCore licensing for the parts
  that are derivative; new code is released under the same terms.
