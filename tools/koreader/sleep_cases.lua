-- Cases of tools/koreader/check_sleep.lua for this plugin: the table is the only part with timers (the
-- minute clock, the life change waiting to go into the log and the idle limit of the awake state).
local function table_screen(plugin_dir, game, format, count, layout)
    -- main.lua does this when KOReader loads the plugin.
    require("matkeeper/awake").install("matkeeper")
    local Screen = require("matkeeper/ui/screen")
    local screen = Screen:new{ plugin_dir = plugin_dir }
    screen.setup = { game = game, format = format, count = count, layout = layout, names = {} }
    screen:fill_defaults()
    screen:setup_go("seats")
    screen:begin_match(false)
    return screen
end

return {
    ["matkeeper/ui/surface"] = "base class of the screen, never opened by itself",
    ["Commander table with a life change waiting"] = function(plugin_dir)
        local screen = table_screen(plugin_dir, "magic", "commander", 4, "r:p.pp.p")
        screen:bump_life(1, -3)
        return screen
    end,
    ["Pokemon table"] = function(plugin_dir)
        return table_screen(plugin_dir, "pokemon", "standard", 2, "r:p.p")
    end,
}
