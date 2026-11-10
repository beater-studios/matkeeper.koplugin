-- A match: players, their scores and counters, the turn, the clock, the log and undo. It knows the
-- rules each game needs (defeat in Magic, conditions and Checkup in Pokémon) and nothing about screens.
local Magic = require("matkeeper/games/magic")
local Pokemon = require("matkeeper/games/pokemon")
local Rng = require("matkeeper/rng")
local SavedState = require("matkeeper/saved_state")

local Match = {}
Match.__index = Match
Match.VERSION = 1
Match.UNDO_LIMIT = 60
Match.GAMES = { magic = Magic, pokemon = Pokemon }
Match.GAME_ORDER = { "magic", "pokemon" }

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for k, v in pairs(value) do
        result[k] = copy(v)
    end
    return result
end

function Match.game(id)
    return Match.GAMES[id]
end

function Match.format(game_id, format_id)
    local game = Match.GAMES[game_id]
    if not game then
        return nil
    end
    for _, format in ipairs(game.formats) do
        if format.id == format_id then
            return format
        end
    end
    return nil
end

-- Rules a player picks for a custom Magic match. Anything missing takes the default.
Match.CUSTOM_DEFAULT = { life = 20, poison = true, commander = false, tax = false }
Match.CUSTOM_LIFE_MIN = 1
Match.CUSTOM_LIFE_MAX = 999

function Match.custom_rules(r)
    r = type(r) == "table" and r or {}
    local d = Match.CUSTOM_DEFAULT
    local life = math.floor(tonumber(r.life) or d.life)
    life = math.max(Match.CUSTOM_LIFE_MIN, math.min(Match.CUSTOM_LIFE_MAX, life))
    local function flag(name)
        if r[name] == nil then
            return d[name]
        end
        return r[name] == true
    end
    return { life = life, poison = flag("poison"), commander = flag("commander"), tax = flag("tax") }
end

-- The custom rules as a format table, the same shape as the fixed ones.
function Match.custom_format(r)
    local base = Match.format("magic", "custom")
    r = Match.custom_rules(r)
    return {
        id = base.id, min = base.min, max = base.max, custom = true,
        life = r.life,
        poison = r.poison and 10 or nil,
        commander_damage = r.commander and 21 or nil,
        tax = r.tax or nil,
    }
end

function Match.starting_life(format, players)
    if not format.life then
        return nil
    end
    if format.life_multiplayer and players > 2 then
        return format.life_multiplayer
    end
    return format.life
end

-- opts: game, format, players = { { name, seat } }, layout, rng, now (a function returning seconds).
function Match.new(opts)
    local format = assert(Match.format(opts.game, opts.format), "unknown format")
    local self = setmetatable({}, Match)
    if format.custom then
        self.custom = Match.custom_rules(opts.custom)
        format = Match.custom_format(self.custom)
    end
    self.version = Match.VERSION
    self.game = opts.game
    self.format = opts.format
    self.layout = opts.layout
    self.rng = opts.rng or Rng.fresh()
    self.now = opts.now or os.time
    local life = Match.starting_life(format, #opts.players)
    self.players = {}
    for i, p in ipairs(opts.players) do
        self.players[i] = {
            name = p.name,
            seat = p.seat or "bottom",
            life = life,
            counters = {},
            damage = {},
            commanders = 1,
            casts = { 0, 0 },
            out = false,
            conditions = {},
            poison = Pokemon.poison_damage,
            reminders = {},
        }
    end
    self.turn = 1
    -- Pokémon always has a player of the turn; without the coin call, the first player starts.
    self.current = Match.GAMES[opts.game].kind == "turn" and 1 or nil
    self.starter = nil
    self.states = {}
    self.log = {}
    self.flips = { turn = 0, results = {} }
    local now = self.now()
    self.clock = { started = now, since = now, total = 0, paused = false, limit = nil }
    self.undo_stack = {}
    self:add_log({ k = "start" })
    return self
end

function Match:rules()
    local format = Match.format(self.game, self.format)
    if format and format.custom then
        return Match.custom_format(self.custom)
    end
    return format
end

function Match:kind()
    return Match.GAMES[self.game].kind
end

---------------------------------------------------------------------------
-- Log and undo
---------------------------------------------------------------------------

function Match:add_log(entry)
    entry.t = self.turn
    self.log[#self.log + 1] = entry
    return entry
end

-- The clock is left out: undoing a life change must not turn back the time played.
local SNAPSHOT_FIELDS = { "players", "turn", "current", "starter", "states" }

function Match:checkpoint()
    local snapshot = { log_size = #self.log }
    for _, field in ipairs(SNAPSHOT_FIELDS) do
        snapshot[field] = copy(self[field])
    end
    local stack = self.undo_stack
    stack[#stack + 1] = snapshot
    if #stack > Match.UNDO_LIMIT then
        table.remove(stack, 1)
    end
end

function Match:can_undo()
    return #self.undo_stack > 0
end

-- Log entries of results that undo does not take back (dice and coins), kept when undoing.
local KEPT_ON_UNDO = { dice = true, coin = true, coins = true, ["until"] = true, roll_start = true, call = true }

function Match:undo()
    local snapshot = table.remove(self.undo_stack)
    if not snapshot then
        return false
    end
    -- Names and the last coin are not changes that undo takes back.
    local kept = {}
    for i, p in ipairs(self.players) do
        kept[i] = { name = p.name, last_coin = p.last_coin }
    end
    for _, field in ipairs(SNAPSHOT_FIELDS) do
        self[field] = snapshot[field]
    end
    for i, p in ipairs(self.players) do
        if kept[i] then
            p.name, p.last_coin = kept[i].name, kept[i].last_coin
        end
    end
    local log = {}
    for i, entry in ipairs(self.log) do
        if i <= snapshot.log_size or KEPT_ON_UNDO[entry.k] then
            log[#log + 1] = entry
        end
    end
    self.log = log
    return true
end

---------------------------------------------------------------------------
-- Clock
---------------------------------------------------------------------------

function Match:elapsed()
    local c = self.clock
    if c.paused then
        return c.total
    end
    return c.total + math.max(0, self.now() - c.since)
end

function Match:minutes()
    return math.floor(self:elapsed() / 60)
end

-- Minutes left on the countdown, or nil without one.
function Match:minutes_left()
    if not self.clock.limit then
        return nil
    end
    return math.max(0, self.clock.limit - self:minutes())
end

function Match:set_paused(paused)
    local c = self.clock
    if c.paused == paused then
        return
    end
    if paused then
        c.total = self:elapsed()
    else
        c.since = self.now()
    end
    c.paused = paused
end

function Match:set_limit(minutes)
    self.clock.limit = minutes
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

function Match:alive()
    local list = {}
    for i, p in ipairs(self.players) do
        if not p.out then
            list[#list + 1] = i
        end
    end
    return list
end

function Match:rename(i, name)
    self.players[i].name = name
end

function Match:change_life(i, delta)
    if delta == 0 then
        return
    end
    self:checkpoint()
    local p = self.players[i]
    p.life = p.life + delta
    self:add_log({ k = "life", p = i, d = delta, v = p.life })
end

function Match:set_life(i, value)
    local p = self.players[i]
    if value == p.life then
        return
    end
    self:checkpoint()
    local delta = value - p.life
    p.life = value
    self:add_log({ k = "life", p = i, d = delta, v = value })
end

function Match:counter(i, name)
    return self.players[i].counters[name] or 0
end

function Match:change_counter(i, name, delta)
    local p = self.players[i]
    local value = math.max(0, (p.counters[name] or 0) + delta)
    if value == (p.counters[name] or 0) then
        return
    end
    self:checkpoint()
    p.counters[name] = value
    self:add_log({ k = "counter", p = i, c = name, d = delta, v = value })
end

function Match:commander_damage(victim, source, k)
    local row = self.players[victim].damage[source]
    return row and row[k] or 0
end

-- Commander damage is combat damage, so it also comes off the life total.
function Match:change_commander_damage(victim, source, k, delta)
    local p = self.players[victim]
    local row = p.damage[source] or { 0, 0 }
    local value = math.max(0, (row[k] or 0) + delta)
    delta = value - (row[k] or 0)
    if delta == 0 then
        return
    end
    self:checkpoint()
    row[k] = value
    p.damage[source] = row
    p.life = p.life - delta
    self:add_log({ k = "commander", p = victim, s = source, n = k, d = delta, v = value, life = p.life })
end

function Match:set_partners(i, partners)
    self:checkpoint()
    self.players[i].commanders = partners and 2 or 1
end

function Match:tax(i, k)
    return 2 * (self.players[i].casts[k] or 0)
end

function Match:change_casts(i, k, delta)
    local p = self.players[i]
    local value = math.max(0, (p.casts[k] or 0) + delta)
    if value == (p.casts[k] or 0) then
        return
    end
    self:checkpoint()
    p.casts[k] = value
    self:add_log({ k = "tax", p = i, n = k, v = 2 * value })
end

-- The monarch and the initiative belong to one player; day and night belong to the game.
function Match:set_state(name, value)
    if self.states[name] == value then
        return
    end
    self:checkpoint()
    self.states[name] = value
    self:add_log({ k = "state", s = name, v = value })
end

-- Why a player has lost under the rules, or nil.
function Match:defeat_reason(i)
    if self:kind() ~= "score" then
        return nil
    end
    local rules = self:rules()
    local p = self.players[i]
    if p.life <= 0 then
        return "life"
    end
    if rules.poison and (p.counters.poison or 0) >= rules.poison then
        return "poison"
    end
    if rules.commander_damage then
        for _, row in pairs(p.damage) do
            for _, value in pairs(row) do
                if value >= rules.commander_damage then
                    return "commander"
                end
            end
        end
    end
    return nil
end

-- Players who reached a defeat and were not handled yet. A player kept in the game ("continue")
-- is not asked again until the reason changes.
function Match:pending_defeats()
    local list = {}
    for _, i in ipairs(self:alive()) do
        local p = self.players[i]
        local reason = self:defeat_reason(i)
        if not reason then
            p.kept = nil
        elseif p.kept ~= reason then
            list[#list + 1] = { player = i, reason = reason }
        end
    end
    return list
end

function Match:keep_playing(i, reason)
    self.players[i].kept = reason
end

function Match:eliminate(i, reason)
    local p = self.players[i]
    if p.out then
        return
    end
    self:checkpoint()
    p.out = true
    p.out_reason = reason
    self:add_log({ k = "out", p = i, why = reason })
end

---------------------------------------------------------------------------
-- Turns, dice and coins
---------------------------------------------------------------------------

function Match:next_turn()
    self:checkpoint()
    self.turn = self.turn + 1
    self:add_log({ k = "turn" })
end

function Match:roll(count, faces)
    local results, sum = {}, 0
    for i = 1, count do
        results[i] = self.rng:int(1, faces)
        sum = sum + results[i]
    end
    self:add_log({ k = "dice", n = count, f = faces, r = results, sum = sum })
    return results, sum
end

-- Everyone still playing rolls a d20; the highest wins, and ties at the top roll again.
function Match:roll_for_start()
    local contenders = self:alive()
    local rounds = {}
    while true do
        local round, best = {}, 0
        for _, i in ipairs(contenders) do
            local value = self.rng:int(1, 20)
            round[#round + 1] = { p = i, v = value }
            best = math.max(best, value)
        end
        rounds[#rounds + 1] = round
        local top = {}
        for _, r in ipairs(round) do
            if r.v == best then
                top[#top + 1] = r.p
            end
        end
        if #top == 1 then
            self.starter = top[1]
            self:add_log({ k = "roll_start", r = rounds, w = top[1] })
            return rounds, top[1]
        end
        contenders = top
    end
end

function Match:flip(player)
    local result = self.rng:coin()
    if player then
        self.players[player].last_coin = result
    end
    self:add_log({ k = "coin", p = player, r = result })
    return result
end

function Match:flip_many(count)
    local results, heads = {}, 0
    for i = 1, count do
        results[i] = self.rng:coin()
        if results[i] == "heads" then
            heads = heads + 1
        end
    end
    self:add_log({ k = "coins", r = results, h = heads })
    return results, heads
end

function Match:flip_until_tails(limit)
    local results, heads = {}, 0
    for _ = 1, limit or 50 do
        local result = self.rng:coin()
        results[#results + 1] = result
        if result == "tails" then
            break
        end
        heads = heads + 1
    end
    self:add_log({ k = "until", r = results, h = heads })
    return results, heads
end

-- Pokémon: one player calls heads or tails, and whoever wins the flip chooses who goes first.
function Match:call_coin(caller, side)
    local result = self.rng:coin()
    local winner = caller
    if result ~= side then
        winner = caller == 1 and 2 or 1
    end
    self:add_log({ k = "call", p = caller, side = side, r = result, w = winner })
    return result, winner
end

function Match:set_starter(i)
    self.starter = i
    if self:kind() == "turn" then
        self.current = i
    end
    self:add_log({ k = "starter", p = i })
end

---------------------------------------------------------------------------
-- Pokémon: reminders, Special Conditions and Checkup
---------------------------------------------------------------------------

function Match:other(i)
    return i == 1 and 2 or 1
end

function Match:toggle_reminder(key)
    local p = self.players[self.current]
    self:checkpoint()
    p.reminders[key] = not p.reminders[key] or nil
    -- Going to the Bench removes every Special Condition.
    if key == "retreat" and p.reminders[key] and next(p.conditions) then
        p.conditions = {}
        p.paralysis_turn = nil
        self:add_log({ k = "clear", p = self.current, why = "retreat" })
    end
end

function Match:set_condition(i, condition, on)
    local p = self.players[i]
    if (p.conditions[condition] or false) == on then
        return
    end
    self:checkpoint()
    if on then
        local exclusive = false
        for _, name in ipairs(Pokemon.exclusive) do
            exclusive = exclusive or name == condition
        end
        if exclusive then
            for _, name in ipairs(Pokemon.exclusive) do
                p.conditions[name] = nil
            end
            p.paralysis_turn = nil
        end
        p.conditions[condition] = true
        if condition == "poison" then
            -- A new Poisoned replaces the old one, so it starts at the usual amount.
            p.poison = Pokemon.poison_damage
        end
        if condition == "paralysis" then
            p.paralysis_turn = self.turn
        end
    else
        p.conditions[condition] = nil
        if condition == "paralysis" then
            p.paralysis_turn = nil
        end
    end
    self:add_log({ k = "condition", p = i, c = condition, on = on, a = condition == "poison" and p.poison or nil })
end

function Match:change_poison(i, delta)
    local p = self.players[i]
    local value = math.max(Pokemon.poison_step, math.min(Pokemon.poison_max, p.poison + delta))
    if value == p.poison then
        return
    end
    self:checkpoint()
    p.poison = value
    self:add_log({ k = "poison", p = i, a = value })
end

function Match:clear_conditions(i, why)
    local p = self.players[i]
    if not next(p.conditions) then
        return
    end
    self:checkpoint()
    p.conditions = {}
    p.paralysis_turn = nil
    self:add_log({ k = "clear", p = i, why = why or "button" })
end

-- The Checkup between this turn and the next: both Active Pokémon, conditions in rule order.
function Match:checkup_steps()
    local steps = {}
    local order = { self.current, self:other(self.current) }
    for _, i in ipairs(order) do
        local p = self.players[i]
        for _, condition in ipairs(Pokemon.checkup_order) do
            if p.conditions[condition] then
                local step = { p = i, c = condition, key = i .. ":" .. condition }
                if condition == "poison" then
                    step.damage = p.poison
                elseif condition == "burn" then
                    step.damage = Pokemon.burn_damage
                    step.coin = true
                elseif condition == "sleep" then
                    step.coin = true
                elseif condition == "paralysis" then
                    -- It recovers at the Checkup after its owner's next turn.
                    step.recovers = self.current == i and p.paralysis_turn ~= nil and self.turn > p.paralysis_turn
                end
                if step.coin and self.flips.turn == self.turn then
                    step.result = self.flips.results[step.key]
                end
                steps[#steps + 1] = step
            end
        end
    end
    return steps
end

-- Flips are kept for the turn, so closing and opening the Checkup again never flips twice.
function Match:flip_checkup(key)
    if self.flips.turn ~= self.turn then
        self.flips = { turn = self.turn, results = {} }
    end
    if self.flips.results[key] then
        return self.flips.results[key]
    end
    local result = self.rng:coin()
    self.flips.results[key] = result
    return result
end

function Match:checkup_ready(steps)
    for _, step in ipairs(steps or self:checkup_steps()) do
        if step.coin and not step.result then
            return false
        end
    end
    return true
end

-- Applies the Checkup (if any), clears the reminders and hands the turn to the other player.
function Match:pass_turn()
    local steps = self:checkup_steps()
    if not self:checkup_ready(steps) then
        return false
    end
    self:checkpoint()
    local logged = {}
    for _, step in ipairs(steps) do
        local p = self.players[step.p]
        local removed = false
        if step.c == "burn" and step.result == "heads" then
            removed = true
        elseif step.c == "sleep" and step.result == "heads" then
            removed = true
        elseif step.c == "paralysis" and step.recovers then
            removed = true
            p.paralysis_turn = nil
        end
        if removed then
            p.conditions[step.c] = nil
        end
        logged[#logged + 1] = { p = step.p, c = step.c, damage = step.damage, r = step.result, removed = removed }
    end
    if #logged > 0 then
        self:add_log({ k = "checkup", steps = logged })
    end
    self.players[self.current].reminders = {}
    self.current = self:other(self.current)
    self.turn = self.turn + 1
    self:add_log({ k = "pass", p = self.current })
    return true
end

---------------------------------------------------------------------------
-- End and saving
---------------------------------------------------------------------------

-- result: { winner = i } or { draw = true } or {} for no winner.
function Match:finish(result)
    self.finished = { winner = result.winner, draw = result.draw or nil, at = self.now() }
    self:set_paused(true)
    self:add_log({ k = "finish", w = result.winner, draw = result.draw or nil })
end

function Match:summary()
    local names = {}
    for i, p in ipairs(self.players) do
        names[i] = p.name
    end
    return {
        version = Match.VERSION,
        game = self.game,
        format = self.format,
        started = self.clock.started,
        minutes = self:minutes(),
        players = names,
        winner = self.finished and self.finished.winner,
        draw = self.finished and self.finished.draw,
        log = copy(self.log),
    }
end

function Match:serialize()
    return {
        version = Match.VERSION,
        game = self.game,
        format = self.format,
        custom = copy(self.custom),
        layout = self.layout,
        players = copy(self.players),
        turn = self.turn,
        current = self.current,
        starter = self.starter,
        states = copy(self.states),
        log = copy(self.log),
        flips = copy(self.flips),
        clock = copy(self.clock),
        finished = copy(self.finished),
    }
end

-- What every player has, for players saved before a field existed.
local function player_defaults()
    return {
        name = "", seat = "bottom", counters = {}, damage = {}, commanders = 1, casts = { 0, 0 }, out = false,
        conditions = {}, poison = Pokemon.poison_damage, reminders = {},
    }
end

local SEATS = { bottom = true, left = true, top = true, right = true }

-- Every part is checked before use: a part of the wrong type drops the whole match (nil), and a field
-- missing from an older save gets its default.
function Match.restore(data, rng, now)
    if not SavedState.is_version(data, Match.VERSION) or not Match.format(data.game, data.format) then
        return nil
    end
    local format = Match.format(data.game, data.format)
    if type(data.players) ~= "table" or type(data.clock) ~= "table" or type(data.log) ~= "table" then
        return nil
    end
    -- A hole in the players drops the match: ipairs and # would stop at it.
    local players = SavedState.list(data.players)
    local count = table.maxn(players)
    if count < format.min or count > format.max then
        return nil
    end
    local score = Match.GAMES[data.game].kind == "score"
    for i = 1, count do
        local p = players[i]
        if type(p) ~= "table" or type(p.name) ~= "string" or not SEATS[p.seat] then
            return nil
        end
        if score and type(p.life) ~= "number" then
            return nil
        end
        players[i] = SavedState.with_defaults(p, player_defaults())
    end
    local self = setmetatable(SavedState.copy(data), Match)
    self.players = players
    self.rng = rng or Rng.fresh()
    self.now = now or os.time
    local at = self.now()
    self.clock = SavedState.with_defaults(data.clock, { started = at, since = at, total = 0, paused = true })
    self.turn = type(data.turn) == "number" and data.turn or 1
    if self:kind() == "turn" then
        self.current = players[data.current] and data.current or 1
    else
        self.current = nil
    end
    self.starter = players[data.starter] and data.starter or nil
    self.states = type(data.states) == "table" and self.states or {}
    self.flips = SavedState.with_defaults(data.flips, { turn = 0, results = {} })
    local log, saved_log = {}, SavedState.list(data.log)
    for i = 1, table.maxn(saved_log) do
        local entry = saved_log[i]
        if type(entry) == "table" and type(entry.k) == "string" then
            log[#log + 1] = entry
        end
    end
    self.log = log
    if format.custom then
        self.custom = Match.custom_rules(self.custom)
    end
    self.undo_stack = {}
    return self
end

return Match
