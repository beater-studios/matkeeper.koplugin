-- Turns match data into the player's language: durations, dates and log entries.
local Text = {}
Text.__index = Text

function Text.new(strings)
    return setmetatable({ t = strings }, Text)
end

function Text:duration(minutes)
    if minutes >= 60 then
        return string.format(self.t.hours, math.floor(minutes / 60), minutes % 60)
    end
    return string.format(self.t.minutes, minutes)
end

-- "Today, 21:02", "Yesterday, 22:40" or "6/11, 20:15", against a reference time.
function Text:when(time, now)
    local day = os.date("*t", time)
    local ref = os.date("*t", now)
    local clock = string.format("%02d:%02d", day.hour, day.min)
    local function key(t)
        return t.year * 1000 + t.yday
    end
    local yesterday = os.date("*t", now - 86400)
    if key(day) == key(ref) then
        return string.format(self.t.today, clock)
    elseif key(day) == key(yesterday) then
        return string.format(self.t.yesterday, clock)
    end
    return string.format("%d/%d, %s", day.day, day.month, clock)
end

function Text:join(names)
    if #names <= 1 then
        return names[1] or ""
    end
    return table.concat(names, ", ", 1, #names - 1) .. self.t.and_word .. names[#names]
end

function Text:heads_count(heads)
    if heads == 0 then
        return self.t.heads_none
    elseif heads == 1 then
        return self.t.heads_one
    end
    return string.format(self.t.heads_many, heads)
end

function Text:side(result)
    return result == "heads" and self.t.heads_lower or self.t.tails_lower
end

function Text:sides(results)
    local list = {}
    for i, r in ipairs(results) do
        list[i] = self:side(r)
    end
    return table.concat(list, ", ")
end

-- One log entry as a sentence. names[i] is the name of player i.
function Text:entry(e, names)
    local t, L = self.t, self.t.log
    local function n(i)
        return names[i] or "?"
    end
    local k = e.k
    if k == "start" then
        return L.start
    elseif k == "life" then
        if e.d < 0 then
            return string.format(L.life_down, n(e.p), -e.d, e.v)
        end
        return string.format(L.life_up, n(e.p), e.d, e.v)
    elseif k == "counter" then
        return string.format(L.counter, n(e.p), t.counters[e.c] or e.c, e.v)
    elseif k == "commander" then
        if e.d > 0 then
            return string.format(L.commander, n(e.p), e.d, n(e.s), e.v)
        end
        return string.format(L.commander_fix, n(e.s), n(e.p), e.v)
    elseif k == "tax" then
        return string.format(L.tax, n(e.p), e.v)
    elseif k == "state" then
        if e.s == "day_night" then
            return e.v == "day" and L.day or e.v == "night" and L.night or L.day_night_none
        end
        if e.v then
            return string.format(L[e.s], n(e.v))
        end
        return L[e.s .. "_none"]
    elseif k == "out" then
        return string.format(L.out, n(e.p), t.reasons[e.why] or "")
    elseif k == "turn" then
        return L.turn
    elseif k == "dice" then
        local values = {}
        for i, v in ipairs(e.r) do
            values[i] = tostring(v)
        end
        return string.format(L.dice, e.n .. "d" .. e.f, table.concat(values, ", "), e.sum)
    elseif k == "coin" then
        if e.p then
            return string.format(L.coin, n(e.p), self:side(e.r))
        end
        return string.format(L.coin_table, self:side(e.r))
    elseif k == "coins" then
        return string.format(L.coins, #e.r, self:sides(e.r))
    elseif k == "until" then
        return string.format(L.until_tails, self:sides(e.r))
    elseif k == "roll_start" then
        local parts = {}
        for _, round in ipairs(e.r) do
            local values = {}
            for _, r in ipairs(round) do
                values[#values + 1] = n(r.p) .. " " .. r.v
            end
            parts[#parts + 1] = table.concat(values, ", ")
        end
        return string.format(L.roll_start, table.concat(parts, "; "), n(e.w))
    elseif k == "call" then
        return string.format(L.call, n(e.p), self:side(e.side), self:side(e.r), n(e.w))
    elseif k == "starter" then
        return string.format(L.starter, n(e.p))
    elseif k == "condition" then
        local key = e.on and L.condition_on or L.condition_off
        return string.format(key, n(e.p), t.conditions_lower[e.c])
    elseif k == "poison" then
        return string.format(L.poison_amount, n(e.p), e.a)
    elseif k == "clear" then
        return string.format(e.why == "retreat" and L.clear_retreat or L.clear_button, n(e.p))
    elseif k == "checkup" then
        local parts = {}
        for _, s in ipairs(e.steps) do
            local condition = t.conditions_lower[s.c]
            if s.damage then
                parts[#parts + 1] = string.format(L.checkup_damage, n(s.p), condition, s.damage)
            end
            if s.r then
                parts[#parts + 1] = string.format(L.checkup_coin, n(s.p), condition, self:side(s.r))
            end
            if s.removed then
                parts[#parts + 1] = string.format(L.checkup_recovered, n(s.p), condition)
            end
        end
        return string.format(L.checkup, table.concat(parts, "; "))
    elseif k == "pass" then
        return string.format(L.pass, n(e.p))
    elseif k == "finish" then
        if e.w then
            return string.format(L.finish_winner, n(e.w))
        end
        return e.draw and L.finish_draw or L.finish_none
    end
    return k
end

local SETUP = { start = true, call = true, starter = true, roll_start = true }

-- The log as lines grouped under headings: { { heading = "Turn 2 · Ana" }, { text = "...", k = "life" } }.
-- The setup (draws, who starts) goes under "Start"; Pokémon turns carry the name of their player.
function Text:log_lines(log, names)
    local owners = {}
    for _, e in ipairs(log) do
        if e.k == "starter" then
            owners[1] = e.p
        elseif e.k == "pass" then
            owners[e.t] = e.p
        end
    end
    local lines, group = {}, nil
    for _, e in ipairs(log) do
        local t = e.t or 1
        local this = (SETUP[e.k] and t == 1) and "start" or t
        if this ~= group then
            group = this
            local heading
            if this == "start" then
                heading = self.t.log_start
            else
                heading = string.format(self.t.log_turn, this)
                if owners[this] and names[owners[this]] then
                    heading = heading .. " · " .. names[owners[this]]
                end
            end
            lines[#lines + 1] = { heading = heading }
        end
        lines[#lines + 1] = { text = self:entry(e, names), k = e.k }
    end
    return lines
end

return Text
