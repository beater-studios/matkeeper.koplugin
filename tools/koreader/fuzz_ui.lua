-- Plays with random taps and holds through the real screens, repainting after each one, to catch
-- interface errors. Covers both games, every layout of each player count and the three languages.
local plugin_dir = assert(os.getenv("PLUGIN_DIR"))

require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
package.path = plugin_dir .. "/?.lua;" .. package.path

local Device = require("device")
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
UIManager:init()
local Geom = require("ui/geometry")
local Layouts = require("matkeeper/layouts")
local Rng = require("matkeeper/rng")
local Screen = require("matkeeper/ui/screen")

local actions = tonumber(os.getenv("ACTIONS") or "250")
local errors, total = 0, 0
local screen = Screen:new{ plugin_dir = plugin_dir }
UIManager:show(screen)
local W, H = screen.dimen.w, screen.dimen.h

local function close_popups()
    while #UIManager._window_stack > 0 and UIManager._window_stack[#UIManager._window_stack].widget ~= screen do
        UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
    end
end

local function run(label, setup, rng)
    for step = 1, actions do
        total = total + 1
        local ok, err = pcall(function()
            close_popups()
            if screen.mode ~= "table" and screen.mode ~= "setup" or step == 1 then
                setup()
            end
            local x, y = rng:int(0, W - 1), rng:int(0, H - 1)
            local ges = { pos = Geom:new{ x = x, y = y } }
            if rng:int(1, 6) == 1 then
                screen:onHold(nil, ges)
            else
                screen:onTap(nil, ges)
            end
            if rng:int(1, 5) == 1 then
                screen:commit_pending()
            end
            UIManager:forceRePaint()
        end)
        if not ok then
            errors = errors + 1
            print(string.format("ERROR (%s, step %d): %s", label, step, tostring(err)))
            if errors > 20 then
                return
            end
        end
    end
end

local function start(game, format, count, layout, seed)
    return function()
        screen:close_dialog()
        screen.match = nil
        screen.setup = { game = game, format = format, count = count, layout = layout, names = {} }
        screen:fill_defaults()
        screen.setup.seats = nil
        screen:setup_go("seats")
        screen:begin_match(seed % 3 == 0)
        screen.match.rng = Rng.new(seed)
    end
end

local seed = 1
for _, lang in ipairs({ "pt", "en", "es" }) do
    screen:set_language(lang)
    run(lang .. " home", function()
        screen:close_dialog()
        screen:show_home()
    end, Rng.new(seed))
    seed = seed + 1
    run(lang .. " setup", function()
        screen:close_dialog()
        screen:start_setup()
    end, Rng.new(seed))
    seed = seed + 1
    run(lang .. " pokemon", start("pokemon", "standard", 2, Layouts.BAR, seed), Rng.new(seed))
    seed = seed + 1
end
for count = 2, 6 do
    for _, layout in ipairs(Layouts.for_players(count, W, H)) do
        local format = count == 2 and "standard" or "commander"
        run("magic " .. layout.id, start("magic", format, count, layout.id, seed), Rng.new(seed))
        seed = seed + 1
    end
end
run("two headed giant", start("magic", "two_headed_giant", 2, Layouts.BAR, seed), Rng.new(seed))
run("brawl", start("magic", "brawl", 4, "r:pp.pp", seed + 1), Rng.new(seed + 1))
screen.custom_rules = { life = 7, poison = false, commander = true, tax = true }
run("custom 6", start("magic", "custom", 6, "r:pp.pp.pp", seed + 2), Rng.new(seed + 2))
screen.custom_rules = { life = 999, poison = true, commander = false, tax = false }
run("custom 3", start("magic", "custom", 3, "r:pp.pe", seed + 3), Rng.new(seed + 3))
-- History and logs after all those matches.
screen:close_dialog()
screen:show_history(1)
for page = 1, 3 do
    screen:show_history(page)
    UIManager:forceRePaint()
end
for i = 1, math.min(#screen.history, 5) do
    screen:show_log(screen.history[i], function() end)
    UIManager:forceRePaint()
end
print(string.format("%d actions, %d errors, %d matches in the history", total, errors, #screen.history))
UIManager:close(screen)
os.exit(errors == 0 and 0 or 1)
