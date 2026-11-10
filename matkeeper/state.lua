-- Reading back koreader/settings/matkeeper.lua: every part is checked on its own, so a save from another
-- version or a damaged one drops only that part and never breaks the opening. Plain Lua, so the tests use it.
local History = require("matkeeper/history")
local Layouts = require("matkeeper/layouts")
local Match = require("matkeeper/match")
local SavedState = require("matkeeper/saved_state")

local State = {}

State.LANGUAGES = { "pt", "en", "es" }

local SEATS = {}
for _, seat in ipairs(Layouts.SEATS) do
    SEATS[seat] = true
end

-- A list of seats with no holes and only known seats, or nil.
local function seats_list(saved)
    if type(saved) ~= "table" then
        return nil
    end
    local seats = SavedState.list(saved)
    local count = table.maxn(seats)
    if count == 0 then
        return nil
    end
    -- A hole is not a known seat either, so a list with one is dropped.
    for i = 1, count do
        if not SEATS[seats[i]] then
            return nil
        end
    end
    return seats
end

-- A layout id that still decodes and has room for exactly count players.
local function layout_for(id, count)
    local layout = Layouts.decode(id)
    return layout and Layouts.players(layout) == count and id or nil
end

-- The last table set up, for "Repeat the last table", or nil when it no longer makes sense.
function State.last(saved)
    if type(saved) ~= "table" then
        return nil
    end
    local format = Match.format(saved.game, saved.format)
    local seats = seats_list(saved.seats)
    if not format or not seats or #seats < format.min or #seats > format.max then
        return nil
    end
    local layout = layout_for(saved.layout, #seats)
    if not layout then
        return nil
    end
    local names = {}
    for i = 1, #seats do
        local name = type(saved.names) == "table" and saved.names[i]
        if type(name) == "string" then
            names[i] = name
        end
    end
    return {
        game = saved.game,
        format = saved.format,
        layout = layout,
        seats = seats,
        names = names,
        custom = saved.custom ~= nil and Match.custom_rules(saved.custom) or nil,
    }
end

-- The layout and seats chosen for each game and player count ("magic:4"). Seats that do not fit the
-- layout are left out; the setup then suggests them again.
function State.layouts(saved)
    local result = {}
    if type(saved) ~= "table" then
        return result
    end
    for key, pref in pairs(saved) do
        local game, count
        if type(key) == "string" then
            game, count = key:match("^(%a+):(%d)$")
        end
        count = tonumber(count)
        if game and Match.game(game) and type(pref) == "table" and layout_for(pref.layout, count) then
            local seats = seats_list(pref.seats)
            result[key] = { layout = pref.layout, seats = seats and #seats == count and seats or nil }
        end
    end
    return result
end

-- The match in progress, or nil when there is none or it cannot be read. A finished match never comes back.
function State.match(saved, warn, rng, now)
    local match = SavedState.restore(function(data)
        return Match.restore(data, rng, now)
    end, saved, warn)
    if match and match.finished then
        return nil
    end
    return match
end

-- default_lang: the language when none was chosen in the plugin (the reader's, see default_language).
-- read(key) returns what was saved under key.
function State.load(read, default_lang, warn)
    return {
        lang = SavedState.one_of(read("lang"), State.LANGUAGES, default_lang),
        match = State.match(read("match"), warn),
        last = State.last(read("last")),
        layouts = State.layouts(read("layouts")),
        custom = Match.custom_rules(read("custom")),
    }
end

-- The finished matches of matkeeper_history.lua.
function State.history(saved)
    return History.valid(saved)
end

return State
