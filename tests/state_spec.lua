package.path = "./?.lua;" .. package.path
local Match = require("matkeeper/match")
local Rng = require("matkeeper/rng")
local SavedState = require("matkeeper/saved_state")
local State = require("matkeeper/state")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAILED: " .. name .. "\n  " .. tostring(err))
    end
end
local function eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%sexpected %s, got %s", label and (label .. ": ") or "", tostring(expected), tostring(actual)), 2)
    end
end

local function load_save(name)
    local chunk = assert(loadfile("tests/saves/" .. name))
    setfenv(chunk, {})
    return chunk()
end

local function reader(data)
    return function(key)
        return SavedState.copy(data[key])
    end
end

local function now()
    return 5000
end

local function load(data)
    return State.load(reader(data), "en")
end

test("every save of an earlier version opens with its match, last table, layouts and history", function()
    local saved = load_save("0.1.0.lua")
    local state = load(saved)
    eq(state.lang, "pt")
    local m = state.match
    assert(m, "the match came back")
    eq(m.format, "commander")
    eq(#m.players, 4)
    eq(m.players[1].life, 27, "life after commander damage")
    eq(m.players[2].counters.poison, 3)
    eq(m.players[1].damage[2][1], 6)
    eq(m.players[3].casts[1], 2)
    eq(m.clock.away, true)
    eq(state.last.layout, "r:p.pp.p")
    eq(state.last.names[4], "Ana")
    eq(state.layouts["pokemon:2"].layout, "r:p.p")
    eq(state.custom.life, 30)
    local history = State.history(load_save("0.1.0_history.lua").matches)
    eq(#history, 2)
    -- The match goes on after it comes back.
    m:change_life(4, -5)
    eq(m.players[4].life, 35)
    assert(m:undo(), "undo works on a restored match")
    eq(m.players[4].life, 40)
end)

test("a match round trips through its saved copy and goes on", function()
    local players = { { name = "A", seat = "bottom" }, { name = "B", seat = "top" } }
    local m = Match.new{ game = "pokemon", format = "standard", players = players, layout = "r:p.p", rng = Rng.new(3), now = now }
    m:set_condition(1, "poison", true)
    m:toggle_reminder("energy")
    local back = State.match(SavedState.copy(m:serialize()), nil, Rng.new(3), now)
    assert(back, "the match came back")
    eq(back.players[1].conditions.poison, m.players[1].conditions.poison)
    eq(back.current, m.current)
    eq(#back.log, #m.log)
    back:flip(1)
    eq(#back.log, #m.log + 1)
end)

test("content that left drops only what used it", function()
    local saved = load_save("0.1.0.lua")
    saved.match.format = "vintage"
    saved.last.layout = "r:p.p"
    saved.layouts["chess:2"] = { layout = "r:p.p" }
    saved.layouts["magic:4"].seats[2] = "under"
    saved.lang = "fr"
    local state = load(saved)
    eq(state.match, nil, "a match of a format that left")
    eq(state.last, nil, "a last table whose layout no longer fits its seats")
    eq(state.layouts["chess:2"], nil, "a game that left")
    eq(state.layouts["magic:4"].layout, "r:p.pp.p", "the layout stays")
    eq(state.layouts["magic:4"].seats, nil, "seats with an unknown seat are suggested again")
    eq(state.lang, "en", "an unknown language falls back")
end)

test("a damaged match is dropped and the rest of the save stays", function()
    local saved = load_save("0.1.0.lua")
    saved.match.players = 5
    saved.layouts = "broken"
    local state = load(saved)
    eq(state.match, nil)
    assert(state.last, "the last table stays")
    eq(next(state.layouts), nil, "damaged layouts become empty")
    saved = load_save("0.1.0.lua")
    saved.match.players[2].life = "forty"
    eq(load(saved).match, nil, "a Magic player without a number for life")
    saved = load_save("0.1.0.lua")
    saved.match.players[3] = nil
    eq(load(saved).match, nil, "a hole in the players")
    local warned
    saved = load_save("0.1.0.lua")
    saved.match.clock = setmetatable({}, { __index = function() error("planted") end })
    eq(State.match(saved.match, function(text) warned = text end), nil, "an error while restoring")
    assert(warned and warned:find("planted"), "the error is reported")
end)

test("fields missing from an older save get their defaults", function()
    local saved = load_save("0.1.0.lua")
    for _, p in ipairs(saved.match.players) do
        p.reminders, p.casts, p.commanders = nil, nil, nil
    end
    saved.match.clock = { started = 100 }
    saved.match.flips, saved.match.states, saved.match.turn = nil, nil, nil
    saved.match.log[3] = nil
    saved.custom = { life = "lots" }
    local state = load(saved)
    local m = assert(state.match, "the match came back")
    eq(m.players[1].casts[1], 0)
    eq(m.players[1].commanders, 1)
    eq(type(m.players[1].reminders), "table")
    eq(m.clock.total, 0)
    eq(m.turn, 1)
    eq(#m.log, 6, "the hole in the log is left out")
    eq(state.custom.life, Match.CUSTOM_DEFAULT.life)
    m:change_casts(2, 1, 1)
    eq(m.players[2].casts[1], 1)
end)

test("a finished match never comes back", function()
    local saved = load_save("0.1.0.lua")
    saved.match.finished = { at = 10 }
    eq(load(saved).match, nil)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
