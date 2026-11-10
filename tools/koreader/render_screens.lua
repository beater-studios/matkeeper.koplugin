-- Opens the real plugin screens in a headless KOReader and saves each one as a PNG, for review.
-- Run with tools/koreader/run_headless.sh tools/koreader/render_screens.lua (OUTPUT_DIR keeps the files).
local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
local out = assert(os.getenv("OUTPUT_DIR"))
local lang = os.getenv("LANG_CODE") or "pt"

require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings:saveSetting("language", lang)
package.path = plugin_dir .. "/?.lua;" .. package.path

local Device = require("device")
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
UIManager:init()
local Geom = require("ui/geometry")
local Rng = require("matkeeper/rng")
local Screen = require("matkeeper/ui/screen")
-- main.lua does this when KOReader loads the plugin.
require("matkeeper/awake").install("matkeeper")

local screen = Screen:new{ plugin_dir = plugin_dir }
UIManager:show(screen)
local shots = 0

local function shot(name)
    UIManager:forceRePaint()
    Device.screen.bb:writePNG(out .. "/" .. name .. ".png")
    shots = shots + 1
end

-- Each touch is followed by a paint, as on the device, so the next one finds the new hit areas.
local function tap(x, y)
    screen:onTap(nil, { pos = Geom:new{ x = x, y = y } })
    UIManager:forceRePaint()
end

local function hold(x, y)
    screen:onHold(nil, { pos = Geom:new{ x = x, y = y } })
    UIManager:forceRePaint()
end

shot("01_home_empty")
screen:start_setup()
shot("02_game")
screen.setup.game = "magic"
screen:setup_go("game")
shot("02_game_magic")
screen:setup_next()
screen.setup.format = "commander"
screen:setup_go("format")
shot("03_format")
screen.setup.format = "custom"
screen:setup_go("format")
shot("03_format_custom")
screen:setup_next()
assert(screen.setup.step == "rules", "a custom match asks for its rules")
shot("03_rules")
tap(470, 292)
tap(300, 500)
tap(300, 570)
assert(screen.setup.custom.life == 21 and screen.setup.custom.commander and not screen.setup.custom.poison, "the rules page changes life and toggles")
hold(130, 292)
assert(screen.setup.custom.life == 11, "a hold takes 10")
shot("03_rules_changed")
screen.setup.format = "commander"
screen:setup_go("format")
screen:setup_next()
screen.setup.count = 4
screen:setup_go("players")
shot("04_players")
screen:setup_next()
shot("05_layouts")
screen.setup.layout = "r:p.pp.p"
screen:setup_go("layout")
screen:setup_next()
screen.setup.names = { "Bruno", "Caio", "Duda", "Ana" }
screen:setup_go("seats")
shot("06_seats")
do
    local Layouts = require("matkeeper/layouts")
    local pane = screen.panes[3]
    local cx, cy = math.floor(pane.x + pane.w / 2), math.floor(pane.y + pane.h / 2)
    local first = screen.setup.seats[2]
    tap(cx, cy)
    assert(screen.setup.seats[2] == Layouts.next_seat(first), "the center button turns the block")
    shot("06_seats_turned")
    tap(cx, cy)
    assert(screen.setup.seats[2] == Layouts.next_seat(Layouts.next_seat(first)), "the button is still under the finger")
    tap(cx, cy)
    tap(cx, cy)
    assert(screen.setup.seats[2] == first, "four turns come back")
end

-- Commander for four, one at each edge.
screen:begin_match(false)
local m = screen.match
m.rng = Rng.new(5)
m:change_life(1, -9)
m:change_commander_damage(1, 4, 1, 9)
m:change_commander_damage(1, 2, 1, 7)
m:set_state("monarch", 2)
m:change_commander_damage(3, 4, 1, 12)
m:change_counter(3, "poison", 3)
m:change_casts(4, 1, 1)
m:set_state("day_night", "day")
screen:show_table()
screen:bump_life(4, -3)
shot("08_magic_commander_4p")
screen:commit_pending()
screen:show_home()
shot("01_home_saved")
screen:show_table()
screen:commit_pending()
screen:open_player_menu(3)
shot("17_magic_player_menu")
screen:close_dialog()
screen:open_markers(1)
shot("19_magic_markers")
screen:close_dialog()
screen:open_keypad(4)
screen.keypad.digits = "25"
screen:open_keypad(4)
shot("20_magic_keypad")
screen:close_dialog()
screen:open_menu()
shot("21_magic_menu")
do
    local before = screen.dialog_seat or "bottom"
    tap(Device.screen:getWidth() - 40, 40)
    local once = screen.dialog_seat
    tap(Device.screen:getWidth() - 40, 40)
    assert(once ~= before and screen.dialog_seat ~= once, "the dialog rotate button stays in its corner")
    shot("21_magic_menu_turned")
    tap(Device.screen:getWidth() - 40, 40)
    tap(Device.screen:getWidth() - 40, 40)
    assert(screen.dialog_seat == before, "four turns come back")
end
screen:open_dice()
shot("22_magic_dice")
screen.dice.count = 3
screen.dice.faces = 6
screen:open_dice(true)
shot("22_magic_dice_3d6")
screen:close_dialog()
screen:open_end(nil)
shot("18_end_match")
screen.end_choice = nil
screen:close_dialog()

-- Touch on the right player's block (seat right): the owner's right half gives life.
local pane = screen.block_panes[3]
local before = m.players[3].life
tap(pane.x + pane.w / 2, pane.y + pane.h - 30)
screen:commit_pending()
-- The right player faces left, so their right hand points to the top of the screen.
assert(m.players[3].life - before == -1, "the bottom of the screen is the right player's left half")
before = m.players[3].life
tap(pane.x + pane.w / 2, pane.y + 30)
screen:commit_pending()
assert(m.players[3].life - before == 1, "the top of the screen is the right player's right half")
before = m.players[1].life
pane = screen.block_panes[1]
hold(pane.x + 60, pane.y + pane.h / 2)
screen:commit_pending()
assert(m.players[1].life - before == 10, "a hold on the top player's right half gives 10")

-- Two players face to face, with the bar.
screen.match = nil
screen.setup = { game = "magic", format = "standard", count = 2, layout = "r:p.p", names = { "Bruno", "Ana" } }
screen.setup.seats = nil
screen:setup_go("seats")
screen:begin_match(false)
screen.match:change_counter(1, "poison", 2)
screen:show_table()
screen:bump_life(2, -3)
shot("07_magic_2p")
screen:commit_pending()

-- Three players in a 2x2 grid with the controls in the empty cell.
screen.setup = { game = "magic", format = "commander", count = 3, layout = "r:pp.pe", names = { "Bruno", "Caio", "Ana" } }
screen:setup_go("seats")
screen:begin_match(false)
screen.match:change_commander_damage(1, 3, 1, 7)
screen.match:change_counter(2, "poison", 4)
screen:show_table()
shot("09_magic_3p_empty_cell")

-- Six players, one of them out.
screen.setup = { game = "magic", format = "commander", count = 6, layout = "r:pp.pp.pp", names = { "Ana", "Bruno", "Caio", "Duda", "Edu", "Fer" } }
screen:setup_go("seats")
screen:begin_match(false)
screen.match:change_life(3, -40)
screen:check_defeats()
screen.match:change_counter(4, "poison", 6)
screen.match:change_commander_damage(6, 1, 1, 15)
screen:show_table()
shot("10_magic_6p")

-- Who starts, by d20.
screen.setup = { game = "magic", format = "commander", count = 4, layout = "r:pp.pp", names = { "Bruno", "Caio", "Ana", "Duda" } }
screen:setup_go("seats")
screen:begin_match(true)
shot("11_magic_who_starts")
screen.roll = nil

-- Who starts with the face to face layout: the round button over the bar begins the match.
screen.setup = { game = "magic", format = "standard", count = 2, layout = "r:p.p", names = { "Bruno", "Ana" } }
screen:setup_go("seats")
screen:begin_match(true)
shot("11_magic_who_starts_2p")
do
    local hub = screen.panes[#screen.panes]
    tap(math.floor(hub.x + hub.w / 2), math.floor(hub.y + hub.h / 2))
    assert(screen.roll == nil, "the round button ends the draw on a table with a bar")
    local before = #screen.history
    screen:leave_table()
    assert(screen.match.clock.paused and screen.match.clock.away, "leaving the table pauses the clock")
    screen:show_table()
    assert(not screen.match.clock.paused, "coming back resumes it")
    screen.setup = { game = "magic", format = "standard", count = 2, layout = "r:p.p", names = {} }
    screen:setup_go("seats")
    screen:begin_match(false)
    assert(#screen.history == before + 1, "a new match keeps the unfinished one in the history")
end

-- A defeat with two players asks to end or keep playing.
screen.setup = { game = "magic", format = "standard", count = 2, layout = "r:p.p", names = { "Bruno", "Ana" } }
screen:setup_go("seats")
screen:begin_match(false)
screen.match:change_life(1, -20)
screen:show_table()
screen:check_defeats()
shot("23_magic_defeat_2p")
screen.end_choice = nil
screen:close_dialog()

-- Pokémon.
screen.setup = { game = "pokemon", names = { "Bruno", "Ana" } }
screen:fill_defaults()
screen:setup_go("seats")
shot("06_seats_pokemon")
do
    local seen = {}
    for _ = 1, 4 do
        local pane = screen.panes[2]
        tap(math.floor(pane.x + pane.w / 2), math.floor(pane.y + pane.h / 2))
        seen[screen.setup.seats[1]] = true
    end
    assert(seen.top and seen.bottom and not seen.left and not seen.right, "the Pokémon panel only lies down")
end
screen:begin_match(true)
screen.match.rng = Rng.new(9)
shot("24_pokemon_coin_call")
screen:close_dialog()
screen.call = nil
local p = screen.match
p:set_starter(2)
p:pass_turn()
p:pass_turn()
p:pass_turn()
p:pass_turn()
p:toggle_reminder("energy")
p:toggle_reminder("supporter")
p:set_condition(2, "sleep", true)
p:set_condition(2, "poison", true)
p:change_poison(2, 10)
p:set_condition(2, "burn", true)
p:set_condition(1, "confusion", true)
p:flip(2)
screen:show_table()
shot("12_pokemon_2p")
screen:open_coins()
screen.coins.count = 3
screen:open_coins(true)
shot("13_pokemon_coins")
screen:close_dialog()
screen:end_turn()
shot("14_pokemon_checkup")
local steps = p:checkup_steps()
for _, step in ipairs(steps) do
    if step.coin and step.c == "burn" then
        p:flip_checkup(step.key)
    end
end
screen:open_checkup()
shot("14_pokemon_checkup_flipped")
for _, step in ipairs(p:checkup_steps()) do
    if step.coin then
        p:flip_checkup(step.key)
    end
end
screen:open_checkup()
shot("14_pokemon_checkup_ready")
screen:close_dialog()
for _, who in ipairs({ 1, 2 }) do
    p.players[who].conditions = { poison = true, burn = true, sleep = true }
end
p.flips = { turn = p.turn, results = {} }
screen:open_checkup()
shot("14_pokemon_checkup_full")
screen:close_dialog()
screen:open_player_menu(1)
shot("25_pokemon_player_menu")
screen:close_dialog()

-- End the match and look at the history and the log.
screen:open_end(2)
screen:finish_match()
shot("15_history")
screen:show_log(screen.history[1], function() end)
shot("16_match_log")
screen:show_settings()
shot("26_settings")
screen:show_home()
shot("01_home")
screen.last = nil
print(string.format("%d screens saved", shots))
UIManager:close(screen)
