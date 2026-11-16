local DataStorage = require("datastorage")
local Device = require("device")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Awake = require("matkeeper/awake")
local Blocks = require("matkeeper/ui/blocks")
local Dialogs = require("matkeeper/ui/dialogs")
local Draw = require("matkeeper/ui/draw")
local History = require("matkeeper/history")
local Layouts = require("matkeeper/layouts")
local Letters = require("matkeeper/letters")
local Match = require("matkeeper/match")
local Pages = require("matkeeper/ui/pages")
local Portrait = require("matkeeper/portrait")
local Refresh = require("matkeeper/refresh")
local Sleep = require("matkeeper/sleep")
local State = require("matkeeper/state")
local Surface = require("matkeeper/ui/surface")
local Text = require("matkeeper/text")

local s = Draw.s

local LANGUAGES = { { "pt", "Português" }, { "en", "English" }, { "es", "Español" } }
local LIFE_COMMIT_SECONDS = 2
-- Updates without a flash in a row: pages are redrawn whole, the table one small pane at a time.
local PAGE_REFRESHES = 8
local TABLE_REFRESHES = 30
-- A table left without a touch for this long lets the device sleep again, so a forgotten one does not
-- drain the battery. The next touch holds it awake again.
local IDLE_SECONDS = 30 * 60
local COUNTDOWNS = { 30, 40, 50, 60 }

-- A list of n entries from a table that may have holes (names never typed are left out).
local function list_of(source, n)
    local list = {}
    for i = 1, n do
        local value = type(source) == "table" and source[i]
        if type(value) == "string" then
            list[i] = value
        end
    end
    return list
end

local function load_table(path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, {})
    return chunk()
end

local function default_language()
    local code = G_reader_settings and G_reader_settings:readSetting("language") or ""
    local prefix = code:sub(1, 2):lower()
    for _, lang in ipairs(LANGUAGES) do
        if lang[1] == prefix then
            return prefix
        end
    end
    return "en"
end

local Screen = Surface:extend{
    name = "matkeeper_screen",
    plugin_dir = ".",
}

function Screen:init()
    Portrait.open(self, self.setup_screen)
end

-- Everything the opening does, protected by Portrait.open: if it fails, the rotation is given back.
function Screen:setup_screen()
    Surface.init(self)
    Draw.init(self.plugin_dir)
    if Device:hasKeys() then
        self.key_events.Back = { { Device.input.group.Back } }
    end
    self.meta = load_table(self.plugin_dir .. "/_meta.lua")
    self.i18n = load_table(self.plugin_dir .. "/data/i18n.lua")
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/matkeeper.lua")
    self.history_file = LuaSettings:open(DataStorage:getSettingsDir() .. "/matkeeper_history.lua")
    local saved = State.load(function(key)
        return self.settings:readSetting(key)
    end, default_language(), logger.warn)
    self.lang = self.i18n[saved.lang] and saved.lang or "en"
    self:set_language(self.lang)
    self.match = saved.match
    self.last = saved.last
    self.prefs = saved.layouts
    self.custom_rules = saved.custom
    self.history = State.history(self.history_file:readSetting("matches"))
    self.page_refresh = Refresh.new(PAGE_REFRESHES)
    self.table_refresh = Refresh.new(TABLE_REFRESHES)
    self.commit_cb = function()
        self:commit_pending()
    end
    self.clock_cb = function()
        self:tick()
    end
    self.idle_cb = function()
        Awake.set(false)
    end
    self:show_home()
end

function Screen:set_language(lang)
    self.lang = lang
    self.t = self.i18n[lang]
    self.text = Text.new(self.t)
end

function Screen:save()
    self.settings:saveSetting("lang", self.lang)
    self.settings:saveSetting("match", self.match and self.match:serialize() or nil)
    self.settings:saveSetting("last", self.last)
    self.settings:saveSetting("layouts", self.prefs)
    self.settings:saveSetting("custom", self.custom_rules)
    self.settings:flush()
end

function Screen:names()
    local names = {}
    for i, p in ipairs(self.match.players) do
        names[i] = p.name
    end
    return names
end

-- The kind of what is on screen picks the mode: a new page or the table opening flash once, changes
-- inside them do not, and a flash comes after PAGE_REFRESHES (pages) or TABLE_REFRESHES (table panes).
-- Pages and the table count apart; moving from one to the other starts the count again.
-- A flash due while a dialog is open (inside) waits for it to close, so the screen does not flash between
-- the taps of a dialog; the change itself is refreshed without one.
function Screen:refresh_mode(inside)
    local counter = self.kind == "table" and self.table_refresh or self.page_refresh
    if counter ~= self.last_counter then
        counter:reset()
        self.last_counter = counter
    end
    local mode = counter:mode(self.kind)
    if inside then
        if mode == "full" then
            self.flash_due = true
        end
        return "ui"
    end
    if self.flash_due then
        self.flash_due = nil
        return "full"
    end
    return mode
end

-- The next refresh flashes, whatever is on screen: after waking up and after a milestone.
function Screen:reset_refresh()
    self.page_refresh:reset()
    self.table_refresh:reset()
    self.flash_due = nil
end

function Screen:page(view)
    self:leave_table()
    self:set_panes({ { x = 0, y = 0, w = self.dimen.w, h = self.dimen.h, seat = "bottom", view = view } }, self.mode)
end

---------------------------------------------------------------------------
-- Home, settings and history
---------------------------------------------------------------------------

function Screen:show_home()
    self.mode = "home"
    self:page(Pages.home{
        t = self.t,
        text = self.text,
        name = self.t.name,
        saved = self.match,
        last = self.last,
        on_close = function() UIManager:close(self) end,
        on_continue = function() self:show_table() end,
        on_new = function() self:start_setup() end,
        on_repeat = function() self:repeat_last() end,
        on_history = function() self:show_history(1) end,
        on_settings = function() self:show_settings() end,
    })
end

function Screen:show_settings()
    self.mode = "settings"
    self:page(Pages.settings{
        t = self.t,
        lang = self.lang,
        languages = LANGUAGES,
        version = self.meta.version,
        on_lang = function(code)
            self:set_language(code)
            self:save()
            self:show_settings()
        end,
        on_back = function() self:show_home() end,
    })
end

function Screen:show_history(page)
    self.mode = "history"
    self:page(Pages.history{
        t = self.t,
        text = self.text,
        list = self.history,
        page = page,
        now = os.time(),
        on_open = function(i) self:show_log(self.history[i], function() self:show_history(page) end) end,
        on_page = function(p) self:show_history(p) end,
        on_back = function() self:show_home() end,
    })
end

-- summary: a history item, or the match being played. back: where the back button goes.
function Screen:show_log(summary, back, page)
    self.mode = "log"
    self.log_back = back
    local names = summary.players
    local subtitle = {}
    subtitle[#subtitle + 1] = self.text:when(summary.started, os.time())
    subtitle[#subtitle + 1] = self.text:duration(summary.minutes or 0)
    if summary.winner then
        subtitle[#subtitle + 1] = string.format(self.t.won, names[summary.winner] or "?")
    elseif summary.draw then
        subtitle[#subtitle + 1] = self.t.draw_result
    end
    self:page(Pages.log{
        t = self.t,
        title = self.t.games_short[summary.game] .. "  ·  " .. (self.t.formats[summary.format] or ""),
        subtitle = table.concat(subtitle, "  ·  "),
        lines = self.text:log_lines(summary.log, names),
        page = page,
        on_page = function(p) self:show_log(summary, back, p) end,
        on_back = back,
    })
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function Screen:start_setup()
    self.setup = { names = {} }
    self:setup_go("game")
end

function Screen:repeat_last()
    local last = self.last
    if not last or not Match.format(last.game, last.format) then
        return self:start_setup()
    end
    self.setup = {
        game = last.game,
        format = last.format,
        count = #last.seats,
        layout = last.layout,
        seats = { unpack(last.seats) },
        names = list_of(last.names, #last.seats),
        custom = last.custom and Match.custom_rules(last.custom),
    }
    self:setup_go("seats")
end

-- The steps this setup goes through: formats, counts and layouts with a single choice are skipped.
function Screen:setup_steps()
    local st = self.setup
    local steps = { "game" }
    local game = st.game and Match.game(st.game)
    if not game then
        return steps
    end
    if #game.formats > 1 then
        steps[#steps + 1] = "format"
    end
    local format = st.format and Match.format(st.game, st.format) or (#game.formats == 1 and game.formats[1])
    if format and format.custom then
        steps[#steps + 1] = "rules"
    end
    if format and format.max > format.min then
        steps[#steps + 1] = "players"
    end
    local count = st.count or (format and format.min == format.max and format.min)
    if count and #self:layouts_for(count) > 1 then
        steps[#steps + 1] = "layout"
    end
    steps[#steps + 1] = "seats"
    return steps
end

function Screen:layouts_for(count)
    if self.setup.game == "pokemon" then
        return { Layouts.decode(Layouts.BAR) }
    end
    return Layouts.for_players(count, self.dimen.w, self.dimen.h)
end

function Screen:step_number(step)
    local steps = self:setup_steps()
    for i, name in ipairs(steps) do
        if name == step then
            return i, #steps
        end
    end
    return #steps, #steps
end

function Screen:setup_go(step)
    self.mode = "setup"
    self.setup.step = step
    local st, t = self.setup, self.t
    local number, total = self:step_number(step)
    if not st.game then
        -- Until the game is chosen the number of steps is unknown.
        total = nil
    end
    local back = function() self:setup_back() end
    if step == "game" then
        self:page(Pages.game{
            t = t, step = number, steps = total, games = Match.GAME_ORDER, selected = st.game,
            on_pick = function(id)
                if st.game ~= id then
                    st.format, st.count, st.layout, st.seats = nil, nil, nil, nil
                end
                st.game = id
                self:setup_go("game")
            end,
            on_continue = function() self:setup_next() end,
            on_back = back,
        })
    elseif step == "format" then
        local game = Match.game(st.game)
        self:page(Pages.format{
            t = t, step = number, steps = total, game = st.game, formats = game.formats, selected = st.format,
            life_of = function(format)
                if format.custom then
                    return (st.custom or self.custom_rules).life
                end
                return Match.starting_life(format, format.min)
            end,
            on_pick = function(id)
                if st.format ~= id then
                    st.count, st.layout, st.seats = nil, nil, nil
                end
                st.format = id
                self:setup_go("format")
            end,
            on_continue = function() self:setup_next() end,
            on_back = back,
        })
    elseif step == "rules" then
        st.custom = st.custom or Match.custom_rules(self.custom_rules)
        local rules = st.custom
        local function changed()
            self.custom_rules = Match.custom_rules(rules)
            self:setup_go("rules")
        end
        self:page(Pages.rules{
            t = t, step = number, steps = total, rules = rules, presets = { 20, 25, 30, 40 },
            on_life = function(delta)
                rules.life = Match.custom_rules({ life = rules.life + delta }).life
                changed()
            end,
            on_preset = function(v)
                rules.life = v
                changed()
            end,
            on_toggle = function(name)
                rules[name] = not rules[name]
                changed()
            end,
            on_continue = function() self:setup_next() end,
            on_back = back,
        })
    elseif step == "players" then
        local format = Match.format(st.game, st.format)
        self:page(Pages.players{
            t = t, step = number, steps = total, min = format.min, max = format.max, selected = st.count,
            format_name = t.formats[format.id],
            on_pick = function(n)
                if st.count ~= n then
                    st.layout, st.seats = nil, nil
                end
                st.count = n
                self:setup_go("players")
            end,
            on_continue = function() self:setup_next() end,
            on_back = back,
        })
    elseif step == "layout" then
        local layouts = self:layouts_for(st.count)
        if not st.layout then
            local pref = self.prefs[st.game .. ":" .. st.count]
            st.layout = pref and Layouts.decode(pref.layout) and pref.layout or layouts[1].id
        end
        self:page(Pages.layouts{
            t = t, step = number, steps = total, count = st.count, layouts = layouts, selected = st.layout, page = st.layout_page,
            on_pick = function(id)
                if st.layout ~= id then
                    st.seats = nil
                end
                st.layout = id
                self:setup_go("layout")
            end,
            on_page = function(p)
                st.layout_page = p
                self:setup_go("layout")
            end,
            on_continue = function() self:setup_next() end,
            on_back = back,
        })
    elseif step == "seats" then
        self:show_seats(number, total)
    end
end

function Screen:fill_defaults()
    local st = self.setup
    local game = Match.game(st.game)
    if not st.format and #game.formats == 1 then
        st.format = game.formats[1].id
    end
    local format = st.format and Match.format(st.game, st.format)
    if format and not st.count and format.min == format.max then
        st.count = format.min
    end
    if st.count and not st.layout then
        local layouts = self:layouts_for(st.count)
        local pref = self.prefs[st.game .. ":" .. st.count]
        st.layout = (pref and Layouts.decode(pref.layout) and pref.layout) or layouts[1].id
    end
end

function Screen:setup_next()
    local st = self.setup
    local current = st.step
    if current == "game" and not st.game then
        return
    elseif current == "format" and not st.format then
        return
    elseif current == "players" and not st.count then
        return
    end
    self:fill_defaults()
    local steps = self:setup_steps()
    for i, name in ipairs(steps) do
        if name == current and steps[i + 1] then
            return self:setup_go(steps[i + 1])
        end
    end
end

function Screen:setup_back()
    local steps = self:setup_steps()
    for i, name in ipairs(steps) do
        if name == self.setup.step then
            if i == 1 then
                return self:show_home()
            end
            return self:setup_go(steps[i - 1])
        end
    end
    self:show_home()
end

function Screen:default_name(i)
    local format = Match.format(self.setup.game, self.setup.format)
    return string.format(format.teams and self.t.team_default or self.t.player_default, i)
end

function Screen:show_seats(number, total)
    local st = self.setup
    local layout = Layouts.decode(st.layout)
    if not st.seats or #st.seats ~= st.count then
        local pref = self.prefs[st.game .. ":" .. st.count]
        if pref and pref.layout == st.layout and pref.seats and #pref.seats == st.count then
            st.seats = { unpack(pref.seats) }
        else
            st.seats = Layouts.suggested_seats(layout)
        end
    end
    local w, h = self.dimen.w, self.dimen.h
    local preview = { x = s(60), y = s(190), w = w - s(120), h = h - s(190) - s(110) }
    local panes = { {
        x = 0, y = 0, w = w, h = h, seat = "bottom",
        view = Pages.seats_frame{
            t = self.t, step = number, steps = total, preview = preview,
            on_back = function() self:setup_back() end,
            on_start = function() self:begin_match(false) end,
            on_draw = function() self:begin_match(true) end,
        },
    } }
    local cells = Layouts.rects(layout, preview.x + s(8), preview.y + s(8), preview.w - s(16), preview.h - s(16), s(8))
    -- The Pokémon panel is drawn only for landscape, so its blocks turn between the two seats that
    -- see the cell lying down.
    local landscape_only = Match.game(st.game).kind == "turn"
    local k = 0
    for _, cell in ipairs(cells) do
        if cell.kind == "p" then
            k = k + 1
            local index = k
            local allowed = landscape_only and Layouts.wide_seats(cell.w, cell.h) or nil
            if allowed and st.seats[index] ~= allowed[1] and st.seats[index] ~= allowed[2] then
                st.seats[index] = allowed[1]
            end
            panes[#panes + 1] = {
                x = cell.x, y = cell.y, w = cell.w, h = cell.h, seat = st.seats[index], fill = Draw.INK,
                view = Pages.seat_block{
                    name = st.names[index] or self:default_name(index),
                    number = index,
                    on_rename = function()
                        self:ask_name(st.names[index] or self:default_name(index), function(name)
                            st.names[index] = name
                            self:setup_go("seats")
                        end)
                    end,
                    on_rotate = function()
                        st.seats[index] = Layouts.next_seat(st.seats[index], allowed)
                        self:setup_go("seats")
                    end,
                },
            }
        end
    end
    self:leave_table()
    self:set_panes(panes, self.mode)
end

function Screen:ask_name(current, on_done)
    local dialog
    dialog = InputDialog:new{
        title = self.t.name_title,
        input = current,
        buttons = { {
            { text = self.t.cancel, id = "close", callback = function() UIManager:close(dialog) end },
            {
                text = self.t.ok,
                is_enter_default = true,
                callback = function()
                    local value = (dialog:getInputText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    UIManager:close(dialog)
                    if value ~= "" then
                        on_done(Letters.cut(Letters.nfc(value), 24))
                    end
                end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- An unfinished match is kept in the history, without a winner, before a new one takes its place.
function Screen:archive_saved()
    local match = self.match
    if match and not match.finished then
        match:finish({})
        self.history = History.add(self.history, match:summary())
        self.history_file:saveSetting("matches", self.history)
        self.history_file:flush()
    end
    self.match = nil
end

function Screen:begin_match(draw)
    self:archive_saved()
    local st = self.setup
    local players = {}
    for i = 1, st.count do
        players[i] = { name = st.names[i] or self:default_name(i), seat = st.seats[i] }
    end
    local custom = Match.format(st.game, st.format).custom and Match.custom_rules(st.custom or self.custom_rules) or nil
    self.match = Match.new{ game = st.game, format = st.format, players = players, layout = st.layout, custom = custom }
    self.prefs[st.game .. ":" .. st.count] = { layout = st.layout, seats = { unpack(st.seats) } }
    local names = {}
    for i = 1, st.count do
        names[i] = st.names[i]
    end
    self.last = { game = st.game, format = st.format, layout = st.layout, seats = { unpack(st.seats) }, names = names, custom = custom }
    self.dialog_seat = "bottom"
    self:save()
    if draw and self.match:kind() == "score" then
        local rounds, winner = self.match:roll_for_start()
        self.roll = { values = {}, winner = winner }
        for _, r in ipairs(rounds[#rounds]) do
            self.roll.values[r.p] = r.v
        end
        self:save()
        self:show_table()
    elseif draw then
        self:show_table()
        self:open_coin_call()
    else
        self:show_table()
    end
end

---------------------------------------------------------------------------
-- The table
---------------------------------------------------------------------------

function Screen:leave_table()
    if self.mode_table then
        self:commit_pending()
        Sleep.unschedule(self, self.clock_cb)
        Sleep.unschedule(self, self.idle_cb)
        Awake.set(false)
        self.mode_table = false
        -- Time away from the table is not play time; a pause chosen by the players stays.
        local match = self.match
        if match and not match.finished and not match.clock.paused then
            match:set_paused(true)
            match.clock.away = true
            self:save()
        end
    end
end

-- The point for the round menu button: the gap junction nearest the center of the screen.
local function hub_point(layout, cells, w, h)
    local candidates = {}
    for b = 1, #layout.bands do
        local band = {}
        for _, cell in ipairs(cells) do
            if cell.band == b then
                band[#band + 1] = cell
            end
        end
        if #band == 2 then
            local a, c = band[1], band[2]
            if layout.columns then
                candidates[#candidates + 1] = { (a.x + a.w / 2), (a.y + a.h + c.y) / 2 }
            else
                candidates[#candidates + 1] = { (a.x + a.w + c.x) / 2, a.y + a.h / 2 }
            end
        end
    end
    for b = 1, #layout.bands - 1 do
        local this, next_band
        for _, cell in ipairs(cells) do
            if cell.band == b then
                this = cell
            elseif cell.band == b + 1 and not next_band then
                next_band = cell
            end
        end
        if layout.columns then
            candidates[#candidates + 1] = { (this.x + this.w + next_band.x) / 2, h / 2 }
        else
            candidates[#candidates + 1] = { w / 2, (this.y + this.h + next_band.y) / 2 }
        end
    end
    local best, distance = { w / 2, h / 2 }, math.huge
    for _, point in ipairs(candidates) do
        local d = (point[1] - w / 2) ^ 2 + (point[2] - h / 2) ^ 2
        if d < distance - 1 then
            best, distance = point, d
        end
    end
    return best[1], best[2]
end

function Screen:show_table()
    local match = self.match
    if not match then
        return self:show_home()
    end
    self.mode = "table"
    self.mode_table = true
    self.pending_player, self.pending = nil, 0
    if match.clock.away then
        match.clock.away = nil
        match:set_paused(false)
    end
    self:touched()
    local w, h = self.dimen.w, self.dimen.h
    local layout = Layouts.decode(match.layout) or Layouts.for_players(#match.players, w, h)[1]
    local margin, gap = s(8), s(8)
    local cells = Layouts.rects(layout, margin, margin, w - 2 * margin, h - 2 * margin, gap, s(56))
    -- The table in miniature, for commander damage by seat: the player cells, in screen coordinates.
    self.table_map = { w = w, h = h, cells = {} }
    for _, cell in ipairs(cells) do
        if cell.kind == "p" then
            local map_cells = self.table_map.cells
            map_cells[#map_cells + 1] = { x = cell.x, y = cell.y, w = cell.w, h = cell.h, player = #map_cells + 1 }
        end
    end
    local panes = {}
    self.block_panes = {}
    self.clock_panes = {}
    local k = 0
    local has_empty = false
    for _, cell in ipairs(cells) do
        if cell.kind == "p" then
            k = k + 1
            local i = k
            local pane = { x = cell.x, y = cell.y, w = cell.w, h = cell.h, seat = match.players[i].seat, fill = Draw.INK }
            pane.view = self:block_view(i)
            panes[#panes + 1] = pane
            self.block_panes[i] = pane
        else
            has_empty = true
            local pane = { x = cell.x, y = cell.y, w = cell.w, h = cell.h, seat = "bottom", fill = Draw.INK }
            pane.view = Blocks.controls{
                match = match, t = self.t, text = self.text,
                on_menu = function() self:open_menu() end,
                on_undo = function() self:undo() end,
                on_dice = function() self:open_dice() end,
                on_coins = function() self:open_coins() end,
                on_clock = function() self:open_clock() end,
            }
            panes[#panes + 1] = pane
            self.clock_panes[#self.clock_panes + 1] = pane
        end
    end
    if cells.bar then
        local pane = { x = cells.bar.x, y = cells.bar.y, w = cells.bar.w, h = cells.bar.h, seat = "bottom", fill = Draw.INK }
        pane.view = Blocks.bar{
            match = match, t = self.t, text = self.text, main = match:kind() == "turn" and "coins" or "dice",
            on_menu = function() self:open_menu() end,
            on_undo = function() self:undo() end,
            on_clock = function() self:open_clock() end,
            on_main = function()
                if match:kind() == "turn" then
                    self:open_coins()
                else
                    self:open_dice()
                end
            end,
        }
        panes[#panes + 1] = pane
        self.clock_panes[#self.clock_panes + 1] = pane
    end
    -- The round button: always without a bar or controls cell, and while showing who starts, as
    -- the only way to begin.
    if self.roll or (not cells.bar and not has_empty) then
        local size = s(80)
        local cx, cy = hub_point(layout, cells, w, h)
        local pane = { x = math.floor(cx - size / 2), y = math.floor(cy - size / 2), w = size, h = size, seat = "bottom", transparent = true }
        pane.view = Blocks.hub{
            match = match,
            play = self.roll ~= nil,
            on_menu = function()
                if self.roll then
                    self.roll = nil
                    self:show_table()
                else
                    self:open_menu()
                end
            end,
        }
        panes[#panes + 1] = pane
    end
    self:set_panes(panes, "table")
    Sleep.schedule(self, 60, self.clock_cb)
end

-- Every touch at the table holds the device awake for another IDLE_SECONDS.
function Screen:touched()
    if self.mode_table then
        Awake.set(true)
        Sleep.schedule(self, IDLE_SECONDS, self.idle_cb)
    end
end

function Screen:block_view(i)
    local match = self.match
    if match:kind() == "turn" then
        return Blocks.pokemon{
            match = match, i = i, t = self.t,
            on_menu = function() self:open_player_menu(i) end,
            on_reminder = function(key) self:act(function() match:toggle_reminder(key) end, i) end,
            on_coin = function() self:act(function() match:flip(i) end, i) end,
            on_condition = function(key) self:act(function() match:set_condition(i, key, not match.players[i].conditions[key]) end, i) end,
            on_poison = function(direction) self:act(function() match:change_poison(i, direction * 10) end, i) end,
            on_clear = function() self:act(function() match:clear_conditions(i) end, i) end,
            on_end_turn = function() self:end_turn() end,
        }
    end
    local o = {
        match = match, i = i, t = self.t,
        on_change = function(delta) self:bump_life(i, delta) end,
        on_keypad = function() self:open_keypad(i) end,
        on_menu = function() self:open_player_menu(i) end,
        on_markers = function() self:open_markers(i) end,
        on_commander = function() self:open_markers(i, 1, "commander") end,
        map = self.table_map,
    }
    if self.roll then
        o.roll = { value = self.roll.values[i] or 0, winner = self.roll.winner == i }
    end
    local view = Blocks.magic(o)
    local draw = view.draw
    view.draw = function(v, ctx)
        o.pending = self.pending_player == i and self.pending or 0
        return draw(v, ctx)
    end
    return view
end

function Screen:update_block(i)
    local pane = self.block_panes and self.block_panes[i]
    if pane then
        self:update(pane)
    end
end

function Screen:update_table()
    if self.mode == "table" then
        self:update(nil)
    end
end

-- Runs a change on the match, saves, and repaints what it touches.
function Screen:act(fn, i)
    self:commit_pending()
    fn()
    self:save()
    if i then
        self:update_block(i)
        for _, pane in ipairs(self.clock_panes or {}) do
            self:update(pane)
        end
    else
        self:update_table()
    end
end

function Screen:bump_life(i, delta)
    if self.roll then
        return
    end
    if self.pending_player and self.pending_player ~= i then
        self:commit_pending()
    end
    self.pending_player = i
    self.pending = (self.pending or 0) + delta
    Sleep.schedule(self, LIFE_COMMIT_SECONDS, self.commit_cb)
    self:update_block(i)
end

function Screen:commit_pending()
    Sleep.unschedule(self, self.commit_cb)
    local i, delta = self.pending_player, self.pending or 0
    self.pending_player, self.pending = nil, 0
    if i and delta ~= 0 and self.match then
        self.match:change_life(i, delta)
        self:save()
        if self.mode == "table" then
            self:update_block(i)
            for _, pane in ipairs(self.clock_panes or {}) do
                self:update(pane)
            end
            local before = self.modal
            self:check_defeats()
            -- True when a defeat opened the end dialog, so the caller does not cover it.
            return self.modal ~= nil and self.modal ~= before
        end
    end
    return false
end

function Screen:undo()
    -- A change still waiting to go into the log is simply dropped.
    if self.pending_player and (self.pending or 0) ~= 0 then
        local i = self.pending_player
        Sleep.unschedule(self, self.commit_cb)
        self.pending_player, self.pending = nil, 0
        self:update_block(i)
        return
    end
    if self.match:undo() then
        self:save()
        self:update_table()
    end
end

function Screen:tick()
    if self.mode ~= "table" then
        return
    end
    -- Outside the refresh count: the minute clock never brings a flash by itself.
    for _, pane in ipairs(self.clock_panes or {}) do
        Surface.update(self, pane, "ui")
    end
    Sleep.schedule(self, 60, self.clock_cb)
end

-- Magic defeats: with more than two players left, the player is out and the match goes on; with
-- two, the end dialog opens with the other one marked, and the match can go on.
function Screen:check_defeats()
    local match = self.match
    local pending = match:pending_defeats()
    if #pending == 0 then
        return
    end
    local first = pending[1]
    local alive = match:alive()
    if #alive > 2 then
        match:eliminate(first.player, first.reason)
        self:save()
        self:update_block(first.player)
        local left = match:alive()
        if #left == 1 then
            self:open_end(left[1])
        else
            self:check_defeats()
        end
    else
        local winner = alive[1] == first.player and alive[2] or alive[1]
        self:open_end(winner, first)
    end
end

---------------------------------------------------------------------------
-- Dialogs
---------------------------------------------------------------------------

-- Where dialogs face: the player of the turn in Pokémon, a chosen side in Magic.
function Screen:table_seat()
    local match = self.match
    if match:kind() == "turn" and match.current then
        return match.players[match.current].seat
    end
    return self.dialog_seat or "bottom"
end

function Screen:rotate_dialogs()
    if self.match:kind() == "turn" then
        return nil
    end
    return function()
        self.dialog_seat = Layouts.next_seat(self.dialog_seat or "bottom")
        self:reopen()
    end
end

function Screen:open_modal(view, seat, on_outside, reopen)
    self.reopen_fn = reopen
    self:show_modal(view, seat, on_outside or function() self:close_dialog() end)
end

function Screen:reopen()
    if self.reopen_fn then
        self.reopen_fn()
    end
end

function Screen:close_dialog()
    self.reopen_fn = nil
    self.player_turn = nil
    self:close_modal()
end

-- Where the dialogs of player i (counters, the player menu, the life keypad) face: the player, until the
-- rotate button turns them towards whoever is using them. The turn lasts until the dialog closes.
function Screen:player_seat(i)
    local turn = self.player_turn
    if turn and turn.i == i then
        return turn.seat
    end
    return self.match.players[i].seat
end

function Screen:turn_player_dialogs(i)
    return function()
        self.player_turn = { i = i, seat = Layouts.next_seat(self:player_seat(i)) }
        self:reopen()
    end
end

function Screen:open_menu(page)
    if self:commit_pending() then
        return
    end
    local match, t = self.match, self.t
    local rows = {}
    rows[#rows + 1] = { label = t.undo, icon = "undo", disabled = not match:can_undo(), on_tap = function()
        self:undo()
        self:open_menu(page)
    end }
    rows[#rows + 1] = { label = t.dice, icon = "d20", on_tap = function() self:open_dice() end }
    rows[#rows + 1] = { label = t.coins, icon = "coins", on_tap = function() self:open_coins() end }
    if match:kind() == "score" then
        rows[#rows + 1] = { label = t.next_turn, icon = "chevron_right", value = string.format(t.turn, match.turn), value_face = "sans", value_px = 15, on_tap = function()
            match:next_turn()
            self:save()
            self:update_table()
            self:open_menu(page)
        end }
        local function holder(name)
            local p = match.states[name]
            return p and match.players[p] and match.players[p].name or t.nobody
        end
        rows[#rows + 1] = { label = t.monarch, icon = "crown", value = holder("monarch"), value_face = "sans", value_px = 15, on_tap = function() self:open_holder("monarch") end }
        rows[#rows + 1] = { label = t.initiative, icon = "star", value = holder("initiative"), value_face = "sans", value_px = 15, on_tap = function() self:open_holder("initiative") end }
        local dn = match.states.day_night
        rows[#rows + 1] = { label = t.day_night, icon = dn == "night" and "moon" or "sun", value = dn == "day" and t.day or dn == "night" and t.night or t.neither, value_face = "sans", value_px = 15, on_tap = function() self:open_day_night() end }
    end
    rows[#rows + 1] = { label = match.clock.paused and t.resume or t.pause, icon = "clock", value = self.text:duration(match:minutes()), value_face = "sans", value_px = 15, on_tap = function()
        match:set_paused(not match.clock.paused)
        self:save()
        self:update_table()
        self:open_menu(page)
    end }
    rows[#rows + 1] = { label = t.countdown, icon = "clock", value = match.clock.limit and string.format(t.minutes, match.clock.limit) or "-", value_face = "sans", value_px = 15, on_tap = function() self:open_countdown() end }
    rows[#rows + 1] = { label = t.history_short, icon = "menu", on_tap = function()
        self:close_dialog()
        local summary = match:summary()
        self:show_log(summary, function() self:show_table() end)
    end }
    rows[#rows + 1] = { kind = "separator" }
    rows[#rows + 1] = { label = t.end_match, on_tap = function() self:open_end(nil) end }
    rows[#rows + 1] = { label = t.leave_table, on_tap = function()
        self:close_dialog()
        self:show_home()
    end }
    local subtitle = self.text:duration(match:minutes()) .. "  ·  " .. string.format(t.turn, match.turn)
    self:open_modal(Dialogs.list{
        title = t.menu_title, subtitle = subtitle, rows = rows, page = page,
        on_page = function(p) self:open_menu(p) end,
        on_rotate = self:rotate_dialogs(),
        buttons = { { text = t.close, style = "filled", on_tap = function() self:close_dialog() end } },
    }, self:table_seat(), nil, function() self:open_menu(page) end)
end

function Screen:open_holder(name)
    local match, t = self.match, self.t
    local rows = {}
    for i, p in ipairs(match.players) do
        rows[#rows + 1] = { label = p.name, radio = true, selected = match.states[name] == i, on_tap = function()
            match:set_state(name, i)
            self:save()
            self:update_table()
            self:open_menu()
        end }
    end
    rows[#rows + 1] = { label = t.nobody, radio = true, selected = match.states[name] == nil, on_tap = function()
        match:set_state(name, nil)
        self:save()
        self:update_table()
        self:open_menu()
    end }
    self:open_modal(Dialogs.list{ title = t[name], rows = rows, on_rotate = self:rotate_dialogs(),
        buttons = { { text = t.back, style = "outline", on_tap = function() self:open_menu() end } } },
        self:table_seat(), nil, function() self:open_holder(name) end)
end

function Screen:open_day_night()
    local match, t = self.match, self.t
    local rows = {}
    for _, entry in ipairs({ { "day", t.day, "sun" }, { "night", t.night, "moon" }, { nil, t.neither } }) do
        rows[#rows + 1] = { label = entry[2], icon = entry[3], selected = match.states.day_night == entry[1], on_tap = function()
            match:set_state("day_night", entry[1])
            self:save()
            self:update_table()
            self:open_menu()
        end }
    end
    self:open_modal(Dialogs.list{ title = t.day_night, rows = rows, on_rotate = self:rotate_dialogs(),
        buttons = { { text = t.back, style = "outline", on_tap = function() self:open_menu() end } } },
        self:table_seat(), nil, function() self:open_day_night() end)
end

function Screen:open_countdown()
    local match, t = self.match, self.t
    local rows = { { label = t.countdown_off, radio = true, selected = match.clock.limit == nil, on_tap = function()
        match:set_limit(nil)
        self:save()
        self:update_table()
        self:open_menu()
    end } }
    for _, minutes in ipairs(COUNTDOWNS) do
        rows[#rows + 1] = { label = string.format(t.minutes, minutes), radio = true, selected = match.clock.limit == minutes, on_tap = function()
            match:set_limit(minutes)
            self:save()
            self:update_table()
            self:open_menu()
        end }
    end
    self:open_modal(Dialogs.list{ title = t.countdown, rows = rows, on_rotate = self:rotate_dialogs(),
        buttons = { { text = t.back, style = "outline", on_tap = function() self:open_menu() end } } },
        self:table_seat(), nil, function() self:open_countdown() end)
end

function Screen:open_clock()
    self:open_menu()
end

function Screen:open_player_menu(i)
    if self:commit_pending() then
        return
    end
    local match, t = self.match, self.t
    local p = match.players[i]
    local rows = {
        { label = t.rename, on_tap = function()
            self:close_dialog()
            self:ask_name(p.name, function(name)
                match:rename(i, name)
                self:save()
                self:update_table()
            end)
        end },
    }
    if match:kind() == "score" then
        rows[#rows + 1] = { label = t.markers, on_tap = function() self:open_markers(i) end }
    end
    if not p.out then
        rows[#rows + 1] = { label = t.concede, danger = true, on_tap = function() self:concede(i) end }
    end
    self:open_modal(Dialogs.list{ title = p.name, rows = rows, on_rotate = self:turn_player_dialogs(i),
        buttons = { { text = t.close, style = "outline", on_tap = function() self:close_dialog() end } } },
        self:player_seat(i), nil, function() self:open_player_menu(i) end)
end

function Screen:concede(i)
    local match = self.match
    local alive = match:alive()
    if #alive > 2 then
        match:eliminate(i, "concede")
        self:save()
        self:close_dialog()
        self:update_table()
        local left = match:alive()
        if #left == 1 then
            self:open_end(left[1])
        end
    else
        local winner = alive[1] == i and alive[2] or alive[1]
        self.conceding = i
        self:open_end(winner)
    end
end

-- The counters of player i, in two tabs when the format has commander damage: "counters" (poison, energy,
-- experience, rad, the commander tax and partners) and "commander" (the damage from each opponent, on the
-- table map, where each one sits).
function Screen:open_markers(i, page, tab)
    if self:commit_pending() then
        return
    end
    local match, t = self.match, self.t
    local p = match.players[i]
    local rules = match:rules()
    local has_map = rules.commander_damage and self.table_map ~= nil
    tab = has_map and tab or "counters"
    local rows = {}
    local function refresh()
        self:save()
        self:update_block(i)
        self:open_markers(i, page, tab)
    end
    if tab == "commander" then
        -- The map as whoever reads the dialog sees the table.
        rows[#rows + 1] = { kind = "map", map = self.table_map, seat = self:player_seat(i), match = match, i = i,
            on_change = function(source, k, delta)
                match:change_commander_damage(i, source, k, delta)
                refresh()
            end }
    else
        for _, name in ipairs(Match.GAMES.magic.counters) do
            rows[#rows + 1] = { kind = "stepper", label = t.counters[name], value = match:counter(i, name),
                on_minus = function() match:change_counter(i, name, -1) refresh() end,
                on_plus = function() match:change_counter(i, name, 1) refresh() end,
                on_minus_hold = function() match:change_counter(i, name, -5) refresh() end,
                on_plus_hold = function() match:change_counter(i, name, 5) refresh() end }
        end
        if rules.tax then
            for k = 1, p.commanders do
                rows[#rows + 1] = { kind = "stepper", label = p.commanders > 1 and string.format(t.tax_label_n, k) or t.tax_label, value = "+" .. match:tax(i, k),
                    on_minus = function() match:change_casts(i, k, -1) refresh() end,
                    on_plus = function() match:change_casts(i, k, 1) refresh() end }
            end
            rows[#rows + 1] = { kind = "toggle", label = t.partners, on = p.commanders > 1, on_tap = function()
                match:set_partners(i, p.commanders == 1)
                self:save()
                self:update_table()
                self:open_markers(i, page, tab)
            end }
        end
    end
    local tabs
    if has_map then
        tabs = {
            { label = t.markers, selected = tab == "counters", on_tap = function() self:open_markers(i, 1, "counters") end },
            { label = t.tab_commander, selected = tab == "commander", on_tap = function() self:open_markers(i, 1, "commander") end },
        }
    end
    self:open_modal(Dialogs.list{
        title = string.format(t.markers_title, p.name), rows = rows, page = page, tabs = tabs, columns = tab == "counters",
        on_rotate = self:turn_player_dialogs(i),
        on_page = function(pg) self:open_markers(i, pg, tab) end,
        buttons = { { text = t.close, style = "filled", on_tap = function()
            self:close_dialog()
            self:check_defeats()
        end } },
    }, self:player_seat(i), function()
        self:close_dialog()
        self:check_defeats()
    end, function() self:open_markers(i, page, tab) end)
end

function Screen:open_keypad(i)
    if self:commit_pending() then
        return
    end
    local match = self.match
    local p = match.players[i]
    self.keypad = self.keypad and self.keypad.player == i and self.keypad or { player = i, digits = "" }
    local state = self.keypad
    local function again()
        self:open_keypad(i)
    end
    self:open_modal(Dialogs.keypad{
        t = self.t, name = p.name, state = state, on_rotate = self:turn_player_dialogs(i),
        on_digit = function(d)
            if #state.digits < 4 then
                state.digits = state.digits .. d
            end
            again()
        end,
        on_back = function()
            state.digits = state.digits:sub(1, -2)
            again()
        end,
        on_clear = function()
            state.digits = ""
            again()
        end,
        on_apply = function(mode)
            local n = tonumber(state.digits) or 0
            if mode == "set" then
                match:set_life(i, n)
            elseif mode == "add" then
                match:change_life(i, n)
            else
                match:change_life(i, -n)
            end
            self.keypad = nil
            self:save()
            self:close_dialog()
            self:update_block(i)
            self:check_defeats()
        end,
    }, self:player_seat(i), function()
        self.keypad = nil
        self:close_dialog()
    end, again)
end

function Screen:open_dice(roll)
    if self:commit_pending() then
        return
    end
    local match = self.match
    self.dice = self.dice or { count = 1, faces = 20 }
    local st = self.dice
    if roll ~= false then
        st.results, st.sum = match:roll(st.count, st.faces)
        self:save()
    end
    self:open_modal(Dialogs.dice{
        t = self.t, state = st, on_rotate = self:rotate_dialogs(),
        on_count = function(d)
            st.count = math.max(1, math.min(10, st.count + d))
            st.results = nil
            self:open_dice(false)
        end,
        on_faces = function(f)
            st.faces = f
            st.results = nil
            self:open_dice(false)
        end,
        on_roll = function() self:open_dice(true) end,
        on_close = function() self:close_dialog() end,
    }, self:table_seat(), nil, function() self:open_dice(false) end)
end

function Screen:open_coins(flip)
    if self:commit_pending() then
        return
    end
    local match = self.match
    self.coins = self.coins or { mode = "count", count = 1 }
    local st = self.coins
    if flip ~= false then
        if st.mode == "until" then
            st.results, st.heads = match:flip_until_tails()
        elseif st.count == 1 then
            local r = match:flip(nil)
            st.results, st.heads = { r }, r == "heads" and 1 or 0
        else
            st.results, st.heads = match:flip_many(st.count)
        end
        self:save()
    end
    self:open_modal(Dialogs.coins{
        t = self.t, text = self.text, state = st, on_rotate = self:rotate_dialogs(),
        on_mode = function(mode)
            st.mode = mode
            st.results = nil
            self:open_coins(false)
        end,
        on_count = function(d)
            st.count = math.max(1, math.min(10, st.count + d))
            st.results = nil
            self:open_coins(false)
        end,
        on_flip = function() self:open_coins(true) end,
        on_close = function() self:close_dialog() end,
    }, self:table_seat(), nil, function() self:open_coins(false) end)
end

function Screen:end_turn()
    local match = self.match
    if #match:checkup_steps() == 0 then
        match:pass_turn()
        self:save()
        self:update_table()
        return
    end
    self:open_checkup()
end

function Screen:open_checkup()
    local match = self.match
    self:open_modal(Dialogs.checkup{
        match = match, t = self.t, steps = match:checkup_steps(),
        on_flip = function(key)
            match:flip_checkup(key)
            self:save()
            self:open_checkup()
        end,
        on_back = function() self:close_dialog() end,
        on_pass = function()
            match:pass_turn()
            self:save()
            self:close_dialog()
            self:update_table()
        end,
    }, self:table_seat(), function() end, function() self:open_checkup() end)
end

function Screen:open_coin_call()
    local match = self.match
    self.call = self.call or {}
    local st = self.call
    local function again()
        self:open_coin_call()
    end
    self:open_modal(Dialogs.coin_call{
        match = match, t = self.t, state = st,
        on_caller = function(i)
            st.caller = i
            again()
        end,
        on_side = function(side)
            st.side = side
            st.result, st.winner = match:call_coin(st.caller, side)
            self:save()
            again()
        end,
        on_start = function(i)
            match:set_starter(i)
            self.call = nil
            self:save()
            self:close_dialog()
            self:update_table()
        end,
        on_skip = function()
            self.call = nil
            self:close_dialog()
        end,
    }, "bottom", function() end, again)
end

-- The end of the match. winner: the player marked at first. defeat: { player, reason } when a
-- defeat opened it, so "keep playing" can leave that player in.
function Screen:open_end(winner, defeat)
    self:commit_pending()
    local match, t = self.match, self.t
    self.end_choice = self.end_choice or { pick = winner and ("p" .. winner) or nil, defeat = defeat }
    local st = self.end_choice
    local rows = {}
    for i, p in ipairs(match.players) do
        local value
        if p.out then
            value = p.out_reason == "concede" and t.conceded or t.out
        elseif self.conceding == i then
            value = t.conceded
        elseif match:kind() == "score" then
            value = tostring(p.life)
        end
        rows[#rows + 1] = { label = p.name, radio = true, selected = st.pick == "p" .. i, value = value,
            value_face = (p.out or self.conceding == i) and "sans" or "serif", value_px = (p.out or self.conceding == i) and 15 or 20,
            on_tap = function()
                st.pick = "p" .. i
                self:open_end()
            end }
    end
    rows[#rows + 1] = { kind = "separator" }
    rows[#rows + 1] = { label = t.draw, radio = true, selected = st.pick == "draw", on_tap = function()
        st.pick = "draw"
        self:open_end()
    end }
    rows[#rows + 1] = { label = t.no_winner, radio = true, selected = st.pick == "none", on_tap = function()
        st.pick = "none"
        self:open_end()
    end }
    local function cancel()
        if st.defeat then
            match:keep_playing(st.defeat.player, st.defeat.reason)
            self:save()
        end
        self.end_choice = nil
        self.conceding = nil
        self:close_dialog()
    end
    local title = t.end_match
    local subtitle = t.who_won
    if st.defeat then
        title = string.format(t.lost_title, match.players[st.defeat.player].name)
        subtitle = t.reasons[st.defeat.reason]
    end
    self:open_modal(Dialogs.list{
        title = title, subtitle = subtitle, rows = rows, on_rotate = self:rotate_dialogs(),
        buttons = {
            { text = st.defeat and t.continue_playing or t.cancel, style = "outline", on_tap = cancel },
            { text = t.finish, style = st.pick and "filled" or "disabled", on_tap = function() self:finish_match() end },
        },
    }, self:table_seat(), function() end, function() self:open_end() end)
end

function Screen:finish_match()
    local match, st = self.match, self.end_choice
    if not st or not st.pick then
        return
    end
    if self.conceding then
        match:eliminate(self.conceding, "concede")
    end
    local result = {}
    if st.pick == "draw" then
        result.draw = true
    elseif st.pick ~= "none" then
        result.winner = tonumber(st.pick:sub(2))
    end
    match:finish(result)
    self.history = History.add(self.history, match:summary())
    self.history_file:saveSetting("matches", self.history)
    self.history_file:flush()
    self.match = nil
    self.end_choice = nil
    self.conceding = nil
    self.roll = nil
    self:save()
    self:close_dialog()
    self:show_history(1)
end

---------------------------------------------------------------------------
-- Life cycle
---------------------------------------------------------------------------

Screen.onSetRotationMode = Portrait.ignore_rotation

-- A pane that failed to draw: a short message and a way back, so the screen never locks.
function Screen:paint_failed(ctx)
    local t = self.t or {}
    local face = Draw.face("bold", s(18))
    local small = Draw.face("sans", s(16))
    local mid = math.floor(ctx.h / 2)
    Draw.text(ctx.bb, t.draw_failed or "This part could not be shown.", face, s(12), mid - s(40), ctx.w - s(24), s(36), "center", Draw.BLACK)
    Draw.text(ctx.bb, t.draw_failed_back or "Tap here to go back.", small, s(12), mid, ctx.w - s(24), s(36), "center", Draw.DARK)
    ctx:hit(0, 0, ctx.w, ctx.h, function()
        if self.mode == "home" and not self.modal then
            UIManager:close(self)
        else
            self:close_dialog()
            self:show_home()
        end
    end)
end

function Screen:dispatch(ges, kind)
    self:touched()
    return Surface.dispatch(self, ges, kind)
end

-- The Back key of devices with keys goes back one screen, and closes the plugin from home.
function Screen:onBack()
    if self.modal then
        if self.modal.on_outside then
            self.modal.on_outside()
        end
    elseif self.mode == "setup" then
        self:setup_back()
    elseif self.mode == "log" and self.log_back then
        self.log_back()
    elseif self.mode == "home" then
        UIManager:close(self)
    else
        self:show_home()
    end
    return true
end

-- KOReader sends Close to every window before it quits (USB mode on a Kobo, closing the window on a computer).
function Screen:onClose(arg)
    if not (arg and arg.keep_screensaver) then
        UIManager:close(self)
    end
end

function Screen:onResume()
    self:reset_refresh()
    self:touched()
end

function Screen:onCloseWidget()
    self:leave_table()
    self:save()
    Surface.onCloseWidget(self)
    Draw.free()
    Portrait.close(self)
    UIManager:setDirty(nil, "full")
end

return Screen
