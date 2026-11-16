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
-- Texts made from a format ("Tax %d", "%s's counters") count too, by a pattern with at least a few
-- letters of their own, so a name alone never matches.
local ui_patterns = {}
for text in pairs(ui_texts) do
    if text:find("%%[%d%.]*[sd]") then
        local parts, pos, letters = {}, 1, 0
        for start, spec, stop in text:gmatch("()%%[%d%.]*([sd])()") do
            local literal = text:sub(pos, start - 1)
            letters = letters + select(2, literal:gsub("%a", ""))
            parts[#parts + 1] = literal:gsub("%p", "%%%0")
            parts[#parts + 1] = spec == "d" and "%-?%d+" or ".+"
            pos = stop
        end
        local rest = text:sub(pos)
        letters = letters + select(2, rest:gsub("%a", ""))
        parts[#parts + 1] = rest:gsub("%p", "%%%0")
        if letters >= 3 then
            ui_patterns[#ui_patterns + 1] = "^" .. table.concat(parts) .. "$"
        end
    end
end
local function is_ui_text(text)
    if ui_texts[text] then
        return true
    end
    for _, pattern in ipairs(ui_patterns) do
        if text:find(pattern) then
            return true
        end
    end
    return false
end
local real_text = Draw.text
Draw.text = function(bb, text, face, x, y, w, h, ...)
    if text and text ~= "" then
        drawn[#drawn + 1] = text
        if is_ui_text(text) and Draw.text_width(text, face) > math.floor(w) + 1 then
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
    -- Commander damage on the table map, from every seat, with partners and a lethal amount.
    local cm = screen.match
    cm:set_partners(3, true)
    cm:change_commander_damage(2, 3, 2, 21)
    cm:change_commander_damage(2, 1, 1, 7)
    cm:change_commander_damage(4, 2, 1, 12)
    screen:update_table()
    check(screen, lang .. " magic commander blocks")
    for i = 1, 4 do
        screen:open_markers(i, 1, "commander")
        check(screen, lang .. " magic commander tab " .. i)
        screen:open_markers(i, 1, "counters")
        check(screen, lang .. " magic counters tab " .. i)
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

-- Commander damage by touch: the map of a block opens the commander tab, and on the large map each
-- opponent (each partner apart) takes on the left half and gives on the right half, from any seat.
start(screen, "magic", "commander", 4, "r:p.pp.p", false)
screen.match:set_partners(1, true)
-- Some damage everywhere, so taking has something to take.
for i, _ in ipairs(screen.match.players) do
    for j, other in ipairs(screen.match.players) do
        if j ~= i then
            for k = 1, other.commanders do
                screen.match:change_commander_damage(i, j, k, 5)
            end
        end
    end
end
screen:update_table()
local function damage_from_all(i)
    local sum = 0
    for j, other in ipairs(screen.match.players) do
        if j ~= i then
            for k = 1, other.commanders do
                sum = sum + screen.match:commander_damage(i, j, k)
            end
        end
    end
    return sum
end
local function tap_local(pane, lx, ly)
    local gx, gy = Layouts.from_local(pane.seat or "bottom", pane.w, pane.h, lx, ly)
    screen:onTap(nil, { pos = Geom:new{ x = pane.x + gx, y = pane.y + gy } })
    UIManager:forceRePaint()
end
for i = 1, 4 do
    local block = screen.block_panes[i]
    UIManager:forceRePaint()
    local map_hit = block.hits[#block.hits]
    drawn = {}
    tap_local(block, map_hit.x + map_hit.w / 2, map_hit.y + map_hit.h / 2)
    if not screen.modal or drew(screen.t.counters.poison) then
        problem("the map of block " .. i .. " did not open the commander tab")
    end
    local hits = {}
    -- Only areas with an action: the box itself swallows taps, and its center may fall on the map.
    for _, hit in ipairs(screen.modal and screen.modal.hits or {}) do
        if hit.tap then
            hits[#hits + 1] = { x = hit.x + hit.w / 2, y = hit.y + hit.h / 2 }
        end
    end
    local plus, minus = 0, 0
    for _, hit in ipairs(hits) do
        -- Closing first brings the dialog back to its player, in case the last tap was the rotate button.
        screen:close_dialog()
        screen:open_markers(i, 1, "commander")
        UIManager:forceRePaint()
        local partners = screen.match.players[i].commanders
        local before = damage_from_all(i)
        tap_local(screen.modal, hit.x, hit.y)
        local delta = damage_from_all(i) - before
        if delta == 1 then
            plus = plus + 1
        elseif delta == -1 then
            minus = minus + 1
        end
        screen.match:set_partners(i, partners > 1)
    end
    screen:close_dialog()
    -- Four opponents' commanders: three players, one of them (player 1) with partners, unless i is player 1.
    local expected = i == 1 and 3 or 4
    if plus ~= expected or minus ~= expected then
        problem(string.format("commander map of player %d: %d parts give and %d take, expected %d", i, plus, minus, expected))
    end
end

-- Fast taps: KOReader handles a batch of queued touches before painting, so the second tap of a batch
-- reaches a dialog the first one reopened and that was never painted. It must count, not close the dialog.
start(screen, "magic", "commander", 4, "r:p.pp.p", false)
screen:open_markers(4, 1, "commander")
UIManager:forceRePaint()
do
    local plus
    for _, hit in ipairs(screen.modal.hits) do
        if hit.tap and hit.hold then
            plus = hit
        end
    end
    local function sum()
        local total = 0
        for j = 1, 3 do
            total = total + screen.match:commander_damage(4, j, 1)
        end
        return total
    end
    local x, y = Layouts.from_local(screen.modal.seat, screen.modal.w, screen.modal.h, plus.x + plus.w / 2, plus.y + plus.h / 2)
    screen:onTap(nil, { pos = Geom:new{ x = x, y = y } })
    screen:onTap(nil, { pos = Geom:new{ x = x, y = y } })
    if not screen.modal or sum() ~= 2 then
        problem(string.format("two fast taps on the commander map: damage %d, dialog %s", sum(), screen.modal and "open" or "closed"))
    end
    screen:close_dialog()
end

-- Taps inside a dialog refresh only what changed: the number of the cell, a counter row, the keypad
-- digits, and nothing behind the dialog. A flash due meanwhile waits for the dialog to close.
do
    local real_refresh = UIManager._refresh
    local sent = {}
    UIManager._refresh = function(self, mode, region, ...)
        sent[#sent + 1] = { mode = mode, area = region and region.w * region.h or W * H }
        return real_refresh(self, mode, region, ...)
    end
    local function tap_hit(hit)
        local x, y = Layouts.from_local(screen.modal.seat, screen.modal.w, screen.modal.h, hit.x + hit.w / 2, hit.y + hit.h / 2)
        screen:onTap(nil, { pos = Geom:new{ x = x, y = y } })
        UIManager:forceRePaint()
    end
    -- hit_of finds, in a painted dialog, the touch area to tap again and again.
    local function check_taps(label, open, hit_of, taps)
        open()
        UIManager:forceRePaint()
        local hit = hit_of(screen.modal.hits)
        sent = {}
        for _ = 1, taps do
            tap_hit(hit)
        end
        for n, entry in ipairs(sent) do
            if entry.mode == "full" or entry.area > W * H / 10 then
                problem(string.format("%s: tap %d refreshed %s on %d of %d pixels", label, n, entry.mode, entry.area, W * H))
                break
            end
        end
        sent = {}
        screen:close_dialog()
        UIManager:forceRePaint()
        return sent[1] and sent[1].mode
    end
    local function last_with(predicate)
        return function(hits)
            local found
            for _, hit in ipairs(hits) do
                if predicate(hit) then
                    found = hit
                end
            end
            return found
        end
    end
    start(screen, "magic", "commander", 4, "r:p.pp.p", false)
    local closing = check_taps("commander map", function() screen:open_markers(4, 1, "commander") end,
        last_with(function(hit) return hit.tap and hit.hold end), 40)
    if closing ~= "full" then
        problem("40 taps in a dialog: the flash due did not come when it closed (" .. tostring(closing) .. ")")
    end
    check_taps("counter row", function() screen:open_markers(4, 1, "counters") end,
        last_with(function(hit) return hit.tap and hit.hold and hit.w < W / 4 end), 12)
    check_taps("life keypad", function() screen:open_keypad(4) end,
        last_with(function(hit) return hit.tap and not hit.hold and hit.h > Draw.s(40) and hit.w < W / 3 end), 3)
    UIManager._refresh = real_refresh
end

-- A player's own dialogs turn with the rotate button, from every seat: the button stays clear of the box,
-- four turns come back to the player, and closing the dialog brings the next one back to the player.
local function rotate_point()
    return W - Draw.s(40), Draw.s(40)
end
local function check_player_dialog(label, i, open)
    open()
    UIManager:forceRePaint()
    local owner = screen.match.players[i].seat
    local modal = screen.modal
    if not modal or modal.seat ~= owner then
        problem(label .. ": does not face its player")
        screen:close_dialog()
        return
    end
    local box = modal.hits[1]
    local bx, by = Layouts.to_local(modal.seat, modal.w, modal.h, rotate_point())
    local r = Draw.s(26)
    if bx + r > box.x and bx - r < box.x + box.w and by + r > box.y and by - r < box.y + box.h then
        problem(label .. ": the rotate button overlaps the box")
    end
    local seat = owner
    for turn = 1, 4 do
        local x, y = rotate_point()
        screen:onTap(nil, { pos = Geom:new{ x = x, y = y } })
        UIManager:forceRePaint()
        seat = Layouts.next_seat(seat)
        if not screen.modal or screen.modal.seat ~= seat then
            problem(string.format("%s: turn %d did not face %s", label, turn, seat))
            break
        end
    end
    screen:close_dialog()
    open()
    if not screen.modal or screen.modal.seat ~= owner then
        problem(label .. ": after closing, does not face its player again")
    end
    screen:close_dialog()
end
for _, case in ipairs({
    { "commander", 4, "r:p.pp.p", false },
    { "commander", 6, "r:pp.pp.pp", true },
}) do
    start(screen, "magic", case[1], case[2], case[3], false)
    if case[4] then
        for i = 1, case[2] do
            screen.match:set_partners(i, true)
        end
    end
    for i = 1, case[2] do
        local where = string.format("%d players, player %d", case[2], i)
        check_player_dialog("counters, " .. where, i, function() screen:open_markers(i, 1, "counters") end)
        check_player_dialog("commander, " .. where, i, function() screen:open_markers(i, 1, "commander") end)
        check_player_dialog("player menu, " .. where, i, function() screen:open_player_menu(i) end)
        check_player_dialog("life keypad, " .. where, i, function() screen:open_keypad(i) end)
    end
end
-- In Pokémon the player menu is a player's only dialog, on a table of two face to face.
start(screen, "pokemon", "standard", 2, Layouts.BAR, false)
for i = 1, 2 do
    check_player_dialog("Pokemon player menu, player " .. i, i, function() screen:open_player_menu(i) end)
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
-- Behind a dialog the clock is covered: it is drawn again when the dialog closes.
expect("clock tick behind a dialog", sequence(function() old:tick() end), "")
old:close_dialog()
expect("clock tick", sequence(function() old:tick() end):gsub(",.*", ""), "ui")
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
