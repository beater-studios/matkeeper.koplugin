-- Opens every page, table and dialog of the plugin in the three languages and checks what a screen size can
-- break: touch areas outside their pane, interface texts cut because they do not fit, the version on the
-- settings page, a match resumed by a new screen (also one saved by 0.1.0), the refresh modes, the Back key
-- and a pane that fails to draw. tools/koreader/check_all_sizes.sh runs it in four screen sizes; OUTPUT_DIR
-- keeps a picture of each screen.
local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
local out_dir = assert(os.getenv("OUTPUT_DIR"))
require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
package.path = plugin_dir .. "/?.lua;" .. package.path
local Device = require("device")
local Screen = Device.screen
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
UIManager:init()
local Geom = require("ui/geometry")
-- main.lua does this when KOReader loads the plugin.
require("matkeeper/awake").install("matkeeper")
local Draw = require("matkeeper/ui/draw")
local Layouts = require("matkeeper/layouts")
local Rng = require("matkeeper/rng")
local PluginScreen = require("matkeeper/ui/screen")
local meta = dofile(plugin_dir .. "/_meta.lua")
local i18n = dofile(plugin_dir .. "/data/i18n.lua")

local problems, screens = 0, 0
local function problem(text)
    problems = problems + 1
    print("PROBLEM: " .. text)
end

-- Every text drawn, and the interface texts cut because they are wider than their box. Player names are
-- left out: a name can be up to 24 letters, and the blocks cut it on purpose.
local drawn, cut = {}, {}
local ui_texts = {}
local function collect(t)
    for _, v in pairs(t) do
        if type(v) == "string" then
            ui_texts[v] = true
        elseif type(v) == "table" then
            collect(v)
        end
    end
end
for _, lang in ipairs({ "pt", "en", "es" }) do
    collect(i18n[lang])
end
local real_text = Draw.text
Draw.text = function(bb, text, face, x, y, w, h, ...)
    if text and text ~= "" then
        drawn[#drawn + 1] = text
        if ui_texts[text] and Draw.text_width(text, face) > math.floor(w) + 1 then
            cut[text] = true
        end
    end
    return real_text(bb, text, face, x, y, w, h, ...)
end

-- Touch areas must stay inside their pane, as its owner sees it.
local function check_hits(screen, name)
    local panes = { unpack(screen.panes) }
    if screen.modal then
        panes[#panes + 1] = screen.modal
    end
    for _, pane in ipairs(panes) do
        local w, h = Layouts.local_size(pane.w, pane.h, pane.seat or "bottom")
        for _, hit in ipairs(pane.hits or {}) do
            if hit.x < -1 or hit.y < -1 or hit.x + hit.w > w + 1 or hit.y + hit.h > h + 1 then
                problem(string.format("%s: touch area %d,%d %dx%d outside its pane of %dx%d", name, hit.x, hit.y, hit.w, hit.h, w, h))
                break
            end
        end
    end
end

local function check(screen, name)
    drawn, cut = {}, {}
    screens = screens + 1
    UIManager:forceRePaint()
    check_hits(screen, name)
    for text in pairs(cut) do
        problem(string.format("%s: text cut: %s", name, text))
    end
    Screen.bb:writePNG(out_dir .. "/" .. name:gsub("[^%w]+", "_") .. ".png")
end

local function drew(text)
    for _, t in ipairs(drawn) do
        if t:find(text, 1, true) then
            return true
        end
    end
    return false
end

local function start(screen, game, format, count, layout, draw)
    screen:close_dialog()
    screen.match, screen.roll = nil, nil
    screen.setup = { game = game, format = format, count = count, layout = layout, names = {} }
    screen:fill_defaults()
    screen:setup_go("seats")
    screen:begin_match(draw)
    screen.match.rng = Rng.new(3)
end

local screen = PluginScreen:new{ plugin_dir = plugin_dir }
UIManager:show(screen)
local W, H = screen.dimen.w, screen.dimen.h

for _, lang in ipairs({ "pt", "en", "es" }) do
    local t = i18n[lang]
    screen:set_language(lang)
    screen.match = nil
    screen:show_home()
    check(screen, lang .. " home")
    screen:show_settings()
    check(screen, lang .. " settings")
    if not drew(string.format(t.version, meta.version)) then
        problem(lang .. " settings: version " .. meta.version .. " missing")
    end
    -- Setup, step by step, with the longest choices.
    screen:start_setup()
    check(screen, lang .. " setup game")
    screen.setup.game = "magic"
    screen:setup_go("game")
    screen:setup_next()
    screen.setup.format = "custom"
    screen:setup_go("format")
    check(screen, lang .. " setup format")
    screen:setup_next()
    check(screen, lang .. " setup rules")
    screen.setup.format = "commander"
    screen:setup_go("format")
    screen:setup_next()
    screen.setup.count = 5
    screen:setup_go("players")
    check(screen, lang .. " setup players")
    screen:setup_next()
    check(screen, lang .. " setup layouts")
    screen:setup_next()
    check(screen, lang .. " setup seats")
    -- Pokémon table and its dialogs.
    start(screen, "pokemon", "standard", 2, Layouts.BAR, false)
    check(screen, lang .. " pokemon table")
    local m = screen.match
    m:set_condition(1, "poison", true)
    m:set_condition(1, "burn", true)
    m:set_condition(2, "sleep", true)
    screen:update_table()
    check(screen, lang .. " pokemon conditions")
    for _, open in ipairs({ "open_menu", "open_coins", "open_clock", "open_checkup", "open_coin_call" }) do
        screen[open](screen)
        check(screen, lang .. " pokemon " .. open)
        screen:close_dialog()
    end
    screen:open_player_menu(1)
    check(screen, lang .. " pokemon player menu")
    screen:close_dialog()
    -- Magic: the dialogs, then the end of the match.
    start(screen, "magic", "commander", 4, "r:p.pp.p", false)
    check(screen, lang .. " magic table")
    for _, open in ipairs({ "open_menu", "open_dice", "open_coins", "open_clock", "open_countdown", "open_day_night" }) do
        screen[open](screen)
        check(screen, lang .. " magic " .. open)
        screen:close_dialog()
    end
    for _, open in ipairs({ "open_player_menu", "open_markers", "open_keypad" }) do
        screen[open](screen, 2)
        check(screen, lang .. " magic " .. open)
        screen:close_dialog()
    end
    screen:open_holder("monarch")
    check(screen, lang .. " magic monarch")
    screen:close_dialog()
    screen:open_end()
    check(screen, lang .. " magic end")
    screen:close_dialog()
    screen.end_choice = { pick = "p1" }
    screen:finish_match()
    check(screen, lang .. " history")
    screen:show_log(screen.history[1], function() screen:show_history(1) end)
    check(screen, lang .. " log")
end

-- Every layout for 2 to 6 players, with the start roll of Magic.
screen:set_language("pt")
for count = 2, 6 do
    for _, layout in ipairs(Layouts.for_players(count, W, H)) do
        start(screen, "magic", count == 2 and "standard" or "commander", count, layout.id, true)
        check(screen, "layout " .. layout.id)
    end
end

-- A match in progress comes back in a new screen, with the same life totals.
start(screen, "magic", "commander", 4, "r:p.pp.p", false)
screen.match:change_life(2, -9)
screen:save()
local expected = screen.match.players[2].life
UIManager:close(screen)
local reopened = PluginScreen:new{ plugin_dir = plugin_dir }
if not reopened.match or reopened.match.players[2].life ~= expected then
    problem("the match in progress was not resumed by a new screen")
end
reopened:free_panes()

-- A save written by 0.1.0 opens, with its match and its last table.
local settings_dir = DataStorage:getSettingsDir()
local function put(source, name)
    local src = assert(io.open(plugin_dir .. "/tests/saves/" .. source, "rb"))
    local data = src:read("*a")
    src:close()
    local dst = assert(io.open(settings_dir .. "/" .. name, "wb"))
    dst:write(data)
    dst:close()
    os.remove(settings_dir .. "/" .. name .. ".old")
end
put("0.1.0.lua", "matkeeper.lua")
put("0.1.0_history.lua", "matkeeper_history.lua")
local old = PluginScreen:new{ plugin_dir = plugin_dir }
UIManager:show(old)
if not old.match or old.match.format ~= "commander" or #old.match.players ~= 4 then
    problem("the match saved by 0.1.0 did not come back")
end
if not old.last or #old.history ~= 2 then
    problem("the last table or the history saved by 0.1.0 did not come back")
end
check(old, "save 0.1.0 home")
old:show_table()
check(old, "save 0.1.0 table")

-- Refresh modes: a new page or the table flashes, changes inside them do not, and a flash comes after
-- 8 page changes or 30 table changes in a row.
local real_set_dirty = UIManager.setDirty
local modes = {}
UIManager.setDirty = function(_, _, refresh)
    modes[#modes + 1] = type(refresh) == "function" and (refresh()) or refresh
end
local function sequence(fn)
    modes = {}
    fn()
    return table.concat(modes, ",")
end
local function expect(label, got, want)
    if got ~= want then
        problem(string.format("refresh %s: %s, expected %s", label, got, want))
    end
end
expect("opening home", sequence(function() old:show_home() end), "full")
expect("settings", sequence(function() old:show_settings() end), "full")
expect("language change", sequence(function() old:set_language("en"); old:show_settings() end), "ui")
expect("table", sequence(function() old:show_table() end), "full")
-- Face to face, so a change refreshes the block and the bar with the clock.
start(old, "magic", "standard", 2, Layouts.BAR, false)
local life = {}
for i = 1, 31 do
    life[i] = sequence(function() old:act(function() old.match:change_life(1, -1) end, 1) end)
end
expect("first table change", life[1], "ui,ui")
local flashes = 0
for _, s in ipairs(life) do
    if s:find("full") then
        flashes = flashes + 1
    end
end
-- Each change refreshes two panes, so 31 changes are 62 refreshes: a flash after each 30.
expect("flashes in 31 table changes", tostring(flashes), "2")
expect("dialog", sequence(function() old:open_dice() end), "ui")
expect("clock tick", sequence(function() old:tick() end):gsub(",.*", ""), "ui")
old:close_dialog()
expect("after waking up", sequence(function() old:reset_refresh(); old:update_table() end), "full")
UIManager.setDirty = real_set_dirty

-- The Back key goes back one screen, and closes the plugin from home.
old:show_table()
old:open_dice()
old:onBack()
if old.modal then problem("Back did not close the dialog") end
old:onBack()
if old.mode ~= "home" then problem("Back from the table did not go home: " .. tostring(old.mode)) end
old:start_setup()
old.setup.game = "magic"
old:setup_go("game")
old:setup_next()
old:onBack()
if old.setup.step ~= "game" then problem("Back in the setup did not go to the step before") end
old:onBack()
if old.mode ~= "home" then problem("Back from the first setup step did not go home") end
old:onBack()
if UIManager:isWidgetShown(old) then problem("Back from home did not close the plugin") end

-- A pane that fails to draw shows a message and a way back, and the screen keeps working.
local broken = PluginScreen:new{ plugin_dir = plugin_dir }
UIManager:show(broken)
broken:show_settings()
broken.panes[1].view.draw = function() error("planted") end
broken.panes[1].dirty = true
local ok, err = pcall(function() UIManager:forceRePaint() end)
if not ok then
    problem("a failing pane broke the paint: " .. tostring(err))
end
check(broken, "draw failed")
broken:onTap(nil, { pos = Geom:new{ x = math.floor(W / 2), y = math.floor(H / 2) } })
UIManager:forceRePaint()
if broken.mode ~= "home" then problem("the failed pane did not lead back home") end
UIManager:close(broken)

print(string.format("%dx%d: %d screens, %d problems", W, H, screens, problems))
os.exit(problems == 0 and 0 or 1)
