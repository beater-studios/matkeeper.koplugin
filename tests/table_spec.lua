package.path = "./?.lua;" .. package.path
local History = require("matkeeper/history")
local Layouts = require("matkeeper/layouts")
local Match = require("matkeeper/match")
local Rng = require("matkeeper/rng")
local Text = require("matkeeper/text")

local function load_i18n()
    local chunk = assert(loadfile("data/i18n.lua"))
    setfenv(chunk, {})
    return chunk()
end

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

local clock = 1000
local function now()
    return clock
end

local function new_match(game, format, count, seed)
    local players = {}
    for i = 1, count do
        players[i] = { name = "P" .. i, seat = "bottom" }
    end
    return Match.new{ game = game, format = format, players = players, layout = "r:p.p", rng = Rng.new(seed or 7), now = now }
end

-- Layouts

test("every player count has layouts, all with the right number of players", function()
    for n = Layouts.MIN_PLAYERS, Layouts.MAX_PLAYERS do
        local list = Layouts.for_players(n, 600, 800)
        assert(#list >= 2, "few layouts for " .. n)
        for _, layout in ipairs(list) do
            eq(Layouts.players(layout), n, layout.id)
            eq(#Layouts.suggested_seats(layout), n, layout.id)
        end
    end
end)

test("the face to face layout comes first for two players", function()
    eq(Layouts.for_players(2, 600, 800)[1].id, Layouts.BAR)
end)

test("layouts round trip through their id", function()
    for n = 2, 6 do
        for _, layout in ipairs(Layouts.for_players(n, 600, 800)) do
            local back = Layouts.decode(layout.id)
            eq(Layouts.encode(back), layout.id)
        end
    end
    eq(Layouts.decode("x:pp"), nil)
    eq(Layouts.decode("r:ppp"), nil)
    eq(Layouts.decode(42), nil)
end)

test("cells fill the area without overlapping", function()
    for n = 2, 6 do
        for _, layout in ipairs(Layouts.for_players(n, 600, 800)) do
            local cells = Layouts.rects(layout, 8, 8, 584, 784, 8, 56)
            for a = 1, #cells do
                local c = cells[a]
                assert(c.x >= 8 and c.y >= 8 and c.x + c.w <= 592 and c.y + c.h <= 792, layout.id .. " out of bounds")
                for b = a + 1, #cells do
                    local d = cells[b]
                    local apart = c.x + c.w <= d.x or d.x + d.w <= c.x or c.y + c.h <= d.y or d.y + d.h <= c.y
                    assert(apart, layout.id .. " overlaps")
                end
            end
        end
    end
end)

test("the face to face layout leaves the bar between the halves", function()
    local cells = Layouts.rects(Layouts.decode(Layouts.BAR), 8, 8, 584, 784, 8, 56)
    assert(cells.bar, "no bar")
    eq(cells.bar.h, 56)
    eq(cells.bar.y, cells[1].y + cells[1].h + 8)
end)

test("suggested seats face the nearest edge", function()
    local seats = Layouts.suggested_seats(Layouts.decode("r:p.pp.p"))
    eq(table.concat(seats, ","), "top,left,right,bottom")
    eq(table.concat(Layouts.suggested_seats(Layouts.decode("r:pp")), ","), "left,right")
    eq(table.concat(Layouts.suggested_seats(Layouts.decode("r:pp.pp")), ","), "top,top,bottom,bottom")
    eq(table.concat(Layouts.suggested_seats(Layouts.decode("c:p.pp")), ","), "left,right,right")
end)

test("touch coordinates turn into the owner's and back", function()
    for _, seat in ipairs(Layouts.SEATS) do
        local w, h = 300, 200
        for _, point in ipairs({ { 0, 0 }, { 299, 0 }, { 0, 199 }, { 120, 77 } }) do
            local lx, ly = Layouts.to_local(seat, w, h, point[1], point[2])
            local lw, lh = Layouts.local_size(w, h, seat)
            assert(lx >= 0 and ly >= 0 and lx < lw and ly < lh, seat .. " outside")
            local bx, by = Layouts.from_local(seat, w, h, lx, ly)
            eq(bx, point[1], seat .. " x")
            eq(by, point[2], seat .. " y")
        end
    end
    -- The owner at the top sees the screen's bottom right corner as their top left.
    local lx, ly = Layouts.to_local("top", 300, 200, 299, 199)
    eq(lx, 0)
    eq(ly, 0)
    -- The owner at the left edge has their bottom along that edge.
    local _, bottom = Layouts.to_local("left", 300, 200, 0, 100)
    eq(bottom, 299)
end)

test("seats turn a quarter at a time", function()
    eq(Layouts.next_seat("bottom"), "left")
    eq(Layouts.next_seat("right"), "bottom")
end)

-- Magic

test("starting life follows the format", function()
    eq(new_match("magic", "standard", 2).players[1].life, 20)
    eq(new_match("magic", "commander", 4).players[1].life, 40)
    eq(new_match("magic", "two_headed_giant", 2).players[1].life, 30)
    eq(new_match("magic", "brawl", 2).players[1].life, 25)
    eq(new_match("magic", "brawl", 3).players[1].life, 30)
end)

test("life changes are logged and undone", function()
    local m = new_match("magic", "standard", 2)
    m:change_life(1, -3)
    m:change_life(1, -2)
    eq(m.players[1].life, 15)
    eq(m.log[#m.log].k, "life")
    eq(m.log[#m.log].v, 15)
    assert(m:undo())
    eq(m.players[1].life, 17)
    eq(m.log[#m.log].v, 17)
    assert(m:undo())
    eq(m.players[1].life, 20)
    eq(#m.log, 1)
    eq(m:undo(), false)
end)

test("defeat by life, poison and commander damage", function()
    local m = new_match("magic", "commander", 4)
    eq(m:defeat_reason(1), nil)
    m:change_life(1, -40)
    eq(m:defeat_reason(1), "life")
    m:change_counter(2, "poison", 10)
    eq(m:defeat_reason(2), "poison")
    for _ = 1, 3 do
        m:change_commander_damage(3, 1, 1, 7)
    end
    eq(m:defeat_reason(3), "commander")
    eq(m.players[3].life, 19)
    eq(#m:pending_defeats(), 3)
end)

test("partners count their damage apart", function()
    local m = new_match("magic", "commander", 2)
    m:set_partners(2, true)
    m:change_commander_damage(1, 2, 1, 15)
    m:change_commander_damage(1, 2, 2, 15)
    eq(m:defeat_reason(1), nil)
    m:change_commander_damage(1, 2, 2, 6)
    eq(m:defeat_reason(1), "commander")
end)

test("Brawl has no commander damage defeat and Two-Headed Giant loses with 15 poison", function()
    local brawl = new_match("magic", "brawl", 2)
    brawl.players[1].damage[2] = { 30 }
    eq(brawl:defeat_reason(1), nil)
    local giant = new_match("magic", "two_headed_giant", 2)
    giant:change_counter(1, "poison", 10)
    eq(giant:defeat_reason(1), nil)
    giant:change_counter(1, "poison", 5)
    eq(giant:defeat_reason(1), "poison")
end)

test("commander tax goes up by 2 per cast", function()
    local m = new_match("magic", "commander", 2)
    m:change_casts(1, 1, 1)
    m:change_casts(1, 1, 1)
    eq(m:tax(1, 1), 4)
    m:change_casts(1, 1, -5)
    eq(m:tax(1, 1), 0)
end)

test("a kept player is not asked again until the reason changes", function()
    local m = new_match("magic", "standard", 2)
    m:change_life(2, -20)
    eq(#m:pending_defeats(), 1)
    m:keep_playing(2, "life")
    eq(#m:pending_defeats(), 0)
    m:change_life(2, 5)
    eq(#m:pending_defeats(), 0)
    m:change_life(2, -10)
    eq(#m:pending_defeats(), 1)
end)

test("eliminated players leave the alive list", function()
    local m = new_match("magic", "commander", 4)
    m:eliminate(3, "concede")
    eq(#m:alive(), 3)
    eq(m.log[#m.log].why, "concede")
    m:undo()
    eq(#m:alive(), 4)
end)

test("the start roll always ends with one winner", function()
    for seed = 1, 200 do
        local m = new_match("magic", "commander", 6, seed)
        local rounds, winner = m:roll_for_start()
        local last = rounds[#rounds]
        local best = 0
        for _, r in ipairs(last) do
            best = math.max(best, r.v)
        end
        local count = 0
        for _, r in ipairs(last) do
            if r.v == best then
                count = count + 1
                eq(r.p, winner)
            end
        end
        eq(count, 1)
    end
end)

test("the clock counts minutes and pauses", function()
    clock = 1000
    local m = new_match("magic", "standard", 2)
    clock = 1000 + 125
    eq(m:minutes(), 2)
    m:set_paused(true)
    clock = 1000 + 900
    eq(m:minutes(), 2)
    m:set_paused(false)
    clock = 1000 + 960
    eq(m:minutes(), 3)
    m:set_limit(50)
    eq(m:minutes_left(), 47)
    m:change_life(1, -1)
    m:undo()
    eq(m:minutes(), 3)
end)

test("a saved match comes back the same", function()
    local m = new_match("magic", "commander", 3)
    m:change_life(2, -7)
    m:change_commander_damage(1, 3, 1, 5)
    m:set_state("monarch", 2)
    local back = Match.restore(m:serialize(), Rng.new(1), now)
    eq(back.players[2].life, 33)
    eq(back:commander_damage(1, 3, 1), 5)
    eq(back.states.monarch, 2)
    eq(#back.log, #m.log)
    eq(Match.restore({ version = 99 }), nil)
end)

-- Pokémon

test("Asleep, Confused and Paralyzed replace each other; markers stay", function()
    local m = new_match("pokemon", "standard", 2)
    m:set_condition(1, "poison", true)
    m:set_condition(1, "sleep", true)
    m:set_condition(1, "paralysis", true)
    local c = m.players[1].conditions
    eq(c.sleep, nil)
    eq(c.paralysis, true)
    eq(c.poison, true)
    m:set_condition(1, "burn", true)
    m:set_condition(1, "confusion", true)
    eq(c.paralysis, nil)
    eq(m.players[1].conditions.confusion, true)
    eq(m.players[1].conditions.burn, true)
end)

test("poison damage moves in steps of 10 and never below 10", function()
    local m = new_match("pokemon", "standard", 2)
    m:change_poison(1, 20)
    eq(m.players[1].poison, 30)
    m:change_poison(1, -100)
    eq(m.players[1].poison, 10)
end)

test("retreating clears the Active's conditions", function()
    local m = new_match("pokemon", "standard", 2)
    m:set_condition(1, "burn", true)
    m:set_condition(1, "sleep", true)
    m:toggle_reminder("retreat")
    eq(next(m.players[1].conditions), nil)
    eq(m.log[#m.log].why, "retreat")
end)

test("the turn passes straight on when no Active has a condition", function()
    local m = new_match("pokemon", "standard", 2)
    m:toggle_reminder("energy")
    eq(#m:checkup_steps(), 0)
    assert(m:pass_turn())
    eq(m.current, 2)
    eq(m.turn, 2)
    eq(next(m.players[1].reminders), nil)
end)

test("Checkup covers both Active Pokémon in rule order", function()
    local m = new_match("pokemon", "standard", 2)
    m:set_condition(1, "sleep", true)
    m:set_condition(1, "burn", true)
    m:set_condition(1, "poison", true)
    m:set_condition(2, "poison", true)
    local steps = m:checkup_steps()
    local order = {}
    for _, step in ipairs(steps) do
        order[#order + 1] = step.p .. step.c
    end
    eq(table.concat(order, ","), "1poison,1burn,1sleep,2poison")
    eq(steps[2].damage, 20)
    eq(steps[1].damage, 10)
end)

test("the turn waits for the Checkup coins, which are flipped only once", function()
    local m = new_match("pokemon", "standard", 2, 3)
    m:set_condition(1, "burn", true)
    eq(m:pass_turn(), false)
    local first = m:flip_checkup("1:burn")
    eq(m:flip_checkup("1:burn"), first)
    eq(m:checkup_steps()[1].result, first)
    assert(m:pass_turn())
    eq(m.players[1].conditions.burn, first == "tails" or nil)
    -- Undoing the pass shows the same coin again.
    m:undo()
    eq(m:checkup_steps()[1].result, first)
end)

test("Paralyzed recovers only after its owner's next turn", function()
    local m = new_match("pokemon", "standard", 2)
    -- Player 1 paralyzes player 2 on turn 1.
    m:set_condition(2, "paralysis", true)
    local step = m:checkup_steps()[1]
    eq(step.recovers, false)
    assert(m:pass_turn())
    eq(m.players[2].conditions.paralysis, true)
    -- Turn 2 is player 2's: the Checkup after it removes the condition.
    eq(m:checkup_steps()[1].recovers, true)
    assert(m:pass_turn())
    eq(m.players[2].conditions.paralysis, nil)
end)

test("the coin call picks the winner", function()
    for seed = 1, 30 do
        local m = new_match("pokemon", "standard", 2, seed)
        local result, winner = m:call_coin(2, "heads")
        eq(winner, result == "heads" and 2 or 1)
        m:set_starter(winner)
        eq(m.current, winner)
    end
end)

test("flipping until tails stops at the first tails", function()
    local m = new_match("pokemon", "standard", 2, 11)
    for _ = 1, 20 do
        local results, heads = m:flip_until_tails()
        eq(results[#results], "tails")
        eq(heads, #results - 1)
    end
end)

test("finishing makes a summary for the history", function()
    local m = new_match("pokemon", "standard", 2)
    m:finish({ winner = 2 })
    local summary = m:summary()
    eq(summary.winner, 2)
    eq(summary.players[2], "P2")
    eq(summary.log[#summary.log].k, "finish")
    local list = {}
    for i = 1, 40 do
        list = History.add(list, { players = {}, log = {}, n = i })
    end
    eq(#list, History.LIMIT)
    eq(list[1].n, 40)
    eq(#History.valid({ { players = {}, log = {} }, "junk", { players = 1 } }), 1)
end)

-- Texts

test("every log entry of a long match reads as a sentence in every language", function()
    local m = new_match("pokemon", "standard", 2, 5)
    m:call_coin(2, "heads")
    m:set_starter(1)
    m:flip(1)
    m:flip_many(3)
    m:flip_until_tails()
    m:set_condition(2, "poison", true)
    m:change_poison(2, 10)
    m:set_condition(1, "burn", true)
    m:set_condition(1, "paralysis", true)
    m:flip_checkup("1:burn")
    m:pass_turn()
    m:toggle_reminder("retreat")
    m:clear_conditions(1)
    m:finish({ winner = 1 })
    local magic = new_match("magic", "commander", 3, 5)
    magic:roll_for_start()
    magic:change_life(1, -4)
    magic:change_life(1, 2)
    magic:change_counter(2, "poison", 3)
    magic:change_commander_damage(3, 1, 1, 6)
    magic:change_commander_damage(3, 1, 1, -2)
    magic:change_casts(1, 1, 1)
    magic:set_state("monarch", 2)
    magic:set_state("monarch", nil)
    magic:set_state("initiative", 3)
    magic:set_state("day_night", "night")
    magic:next_turn()
    magic:roll(2, 6)
    magic:eliminate(2, "concede")
    magic:finish({ draw = true })
    for lang, strings in pairs(load_i18n()) do
        local text = Text.new(strings)
        for _, match in ipairs({ m, magic }) do
            local names = {}
            for i, p in ipairs(match.players) do
                names[i] = p.name
            end
            for _, line in ipairs(text:log_lines(match.log, names)) do
                local value = line.heading or line.text
                assert(type(value) == "string" and value ~= "", lang .. ": empty line")
                assert(not value:find("^%a+$") or line.heading, lang .. ": raw key " .. value)
            end
        end
    end
end)

test("durations, joins and coin counts", function()
    local text = Text.new(load_i18n().pt)
    eq(text:duration(38), "38 min")
    eq(text:duration(84), "1h 24min")
    eq(text:join({ "Ana" }), "Ana")
    eq(text:join({ "Ana", "Bruno", "Caio" }), "Ana, Bruno e Caio")
    eq(text:heads_count(0), "Nenhuma cara")
    eq(text:heads_count(2), "2 caras")
    local base = os.time({ year = 2026, month = 11, day = 8, hour = 22 })
    eq(text:when(base - 3600, base), "Hoje, 21:00")
    eq(text:when(base - 86400, base), "Ontem, 22:00")
end)

test("Pokémon turns carry their player in the log headings", function()
    local m = new_match("pokemon", "standard", 2)
    m:set_starter(2)
    m:pass_turn()
    local lines = Text.new(load_i18n().pt):log_lines(m.log, { "Ana", "Bruno" })
    eq(lines[1].heading, "Início")
    local headings = {}
    for _, line in ipairs(lines) do
        if line.heading then
            headings[#headings + 1] = line.heading
        end
    end
    eq(headings[#headings], "Turno 2 · Ana")
end)

test("custom magic rules set life and defeats", function()
    local players = {}
    for i = 1, 5 do
        players[i] = { name = "P" .. i }
    end
    local m = Match.new{ game = "magic", format = "custom", players = players, layout = "r:p.pp.pp",
        custom = { life = 45, poison = false, commander = true, tax = true }, rng = Rng.new(3), now = now }
    eq(m.players[5].life, 45)
    eq(m:rules().commander_damage, 21)
    eq(m:rules().tax, true)
    m:change_counter(1, "poison", 12)
    eq(m:defeat_reason(1), nil, "poison off")
    m:change_commander_damage(2, 1, 1, 21)
    eq(m:defeat_reason(2), "commander")
    local back = Match.restore(m:serialize(), Rng.new(1), now)
    eq(back.custom.life, 45)
    eq(back:rules().poison, nil)
end)

test("custom magic rules are clamped and default", function()
    local r = Match.custom_rules({ life = 5000, tax = "yes" })
    eq(r.life, Match.CUSTOM_LIFE_MAX)
    eq(r.poison, true)
    eq(r.commander, false)
    eq(r.tax, false)
    eq(Match.custom_rules({ life = -3 }).life, Match.CUSTOM_LIFE_MIN)
    local m = new_match("magic", "custom", 2)
    eq(m.players[1].life, 20)
    m:change_counter(1, "poison", 10)
    eq(m:defeat_reason(1), "poison")
end)

test("landscape-only blocks turn between two seats", function()
    eq(Layouts.next_seat("bottom", Layouts.wide_seats(600, 380)), "top")
    eq(Layouts.next_seat("top", Layouts.wide_seats(600, 380)), "bottom")
    eq(Layouts.next_seat("left", Layouts.wide_seats(300, 800)), "right")
    eq(Layouts.next_seat("bottom", Layouts.wide_seats(300, 800)), "left")
    eq(Layouts.next_seat("right"), "bottom")
end)

test("undo keeps names, coins and dice results", function()
    local m = new_match("magic", "standard", 2)
    m:change_life(1, -3)
    m:rename(1, "Ana")
    local size = #m.log
    m:roll(2, 6)
    m:undo()
    eq(m.players[1].life, 20)
    eq(m.players[1].name, "Ana")
    eq(m.log[#m.log].k, "dice", "the roll stays in the log")
    eq(#m.log, size, "only the life change left the log")
end)

test("a new poisoning starts at the usual amount", function()
    local m = new_match("pokemon", "standard", 2)
    m:set_condition(1, "poison", true)
    m:change_poison(1, 30)
    eq(m.players[1].poison, 40)
    m:clear_conditions(1)
    m:set_condition(1, "poison", true)
    eq(m.players[1].poison, 10)
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
