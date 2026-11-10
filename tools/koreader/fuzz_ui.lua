-- Random taps, holds and swipes through the real screens, with tools/koreader/fuzz.lua: home, setup and the
-- Pokémon table in the three languages, every layout of Magic for 2 to 6 players, Two-Headed Giant, Brawl
-- and two custom matches. Each run starts from nothing saved, with the match dice and coins tied to the seed.
-- Run with tools/koreader/run_headless.sh tools/koreader/fuzz_ui.lua (ACTIONS, SEED, ONLY, MAX_ERRORS).
local Fuzz = dofile(os.getenv("PLUGIN_DIR") .. "/tools/koreader/fuzz.lua")
-- main.lua does this when KOReader loads the plugin.
require("matkeeper/awake").install("matkeeper")
local Layouts = require("matkeeper/layouts")
local Match = require("matkeeper/match")
local Rng = require("matkeeper/rng")
local Screen = require("matkeeper/ui/screen")

local screen = Screen:new{ plugin_dir = Fuzz.plugin_dir }
local fuzz = Fuzz.new{ screen = screen }
local W, H = fuzz.width, fuzz.height

-- What an earlier run left: the match, the history, the last table and the chosen layouts.
local function fresh(lang)
    screen:close_dialog()
    screen:leave_table()
    screen.match, screen.last, screen.roll = nil, nil, nil
    screen.history, screen.prefs = {}, {}
    screen.custom_rules = Match.custom_rules(nil)
    screen:set_language(lang)
end

local function start(lang, game, format, count, layout, seed, custom)
    return function()
        fresh(lang)
        screen.custom_rules = Match.custom_rules(custom)
        screen.setup = { game = game, format = format, count = count, layout = layout, names = {}, custom = custom }
        screen:fill_defaults()
        screen:setup_go("seats")
        screen:begin_match(seed % 3 == 0)
        screen.match.rng = Rng.new(seed)
    end
end

-- The run goes back to the table when a touch left it (home, history, a log).
local function left_table()
    return screen.mode ~= "table" and screen.mode ~= "setup"
end

local seed = 1
for _, lang in ipairs({ "pt", "en", "es" }) do
    fuzz:run{ label = lang .. " home", setup = function()
        fresh(lang)
        screen:show_home()
    end }
    fuzz:run{ label = lang .. " setup", setup = function()
        fresh(lang)
        screen:start_setup()
    end, again = function() return screen.mode == "home" end }
    fuzz:run{ label = lang .. " pokemon", setup = start(lang, "pokemon", "standard", 2, Layouts.BAR, seed), again = left_table }
    seed = seed + 1
end
for count = 2, 6 do
    for _, layout in ipairs(Layouts.for_players(count, W, H)) do
        local format = count == 2 and "standard" or "commander"
        fuzz:run{ label = "magic " .. layout.id, setup = start("pt", "magic", format, count, layout.id, seed), again = left_table }
        seed = seed + 1
    end
end
fuzz:run{ label = "two headed giant", setup = start("en", "magic", "two_headed_giant", 2, Layouts.BAR, seed), again = left_table }
fuzz:run{ label = "brawl", setup = start("es", "magic", "brawl", 4, "r:pp.pp", seed + 1), again = left_table }
fuzz:run{ label = "custom 6", setup = start("pt", "magic", "custom", 6, "r:pp.pp.pp", seed + 2,
    { life = 7, poison = false, commander = true, tax = true }), again = left_table }
fuzz:run{ label = "custom 3", setup = start("en", "magic", "custom", 3, "r:pp.pe", seed + 3,
    { life = 999, poison = true, commander = false, tax = false }), again = left_table }
-- History and logs after a few matches, so the pages have something to show.
fuzz:run{ label = "history", setup = function()
    fresh("pt")
    for i = 1, 4 do
        start("pt", "magic", "commander", 4, "r:p.pp.p", 100 + i)()
        screen.match:change_life(1, -i)
        screen.end_choice = { pick = "p" .. (i % 4 + 1) }
        screen:finish_match()
    end
    screen:show_history(1)
end, again = function() return screen.mode ~= "history" and screen.mode ~= "log" end }
fuzz:finish()
