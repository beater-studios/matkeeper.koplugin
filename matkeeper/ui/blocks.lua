local Draw = require("matkeeper/ui/draw")
local TableMap = require("matkeeper/ui/table_map")

-- The views of the table: a block per player (Magic score or Pokémon turn panel), the bar between
-- two players face to face, the round menu button and the controls cell. Each one draws in its
-- owner's orientation, in ctx.w x ctx.h, and marks its touch areas with ctx:hit.
local Blocks = {}

local s = Draw.s

local function clamp(v, low, high)
    return math.max(low, math.min(high, v))
end

---------------------------------------------------------------------------
-- Magic
---------------------------------------------------------------------------

local function magic_chips(o)
    local match, i, t = o.match, o.i, o.t
    local p = match.players[i]
    local list = {}
    local icons = { poison = "drop", energy = "bolt", experience = "star", rad = "sun" }
    for _, name in ipairs({ "poison", "energy", "experience", "rad" }) do
        local value = p.counters[name] or 0
        if value > 0 then
            local label = name == "poison" and tostring(value) or (t.counters[name] .. " " .. value)
            list[#list + 1] = { icon = icons[name], text = name == "poison" and label or label }
        end
    end
    if match:rules().tax then
        for k = 1, p.commanders do
            local tax = match:tax(i, k)
            if tax > 0 then
                list[#list + 1] = { text = string.format(t.tax, tax) }
            end
        end
    end
    return list
end

-- opts: match, i, t (strings), pending (delta not yet committed), on_change(delta), on_keypad(),
-- on_menu(), on_markers(), roll ({ value, winner } while drawing who starts), map (the table in
-- miniature, for commander damage by seat) and on_commander().
function Blocks.magic(o)
    return { draw = function(_, ctx)
        local bb, w, h = ctx.bb, ctx.w, ctx.h
        local match, i, t = o.match, o.i, o.t
        local p = match.players[i]
        local m = s(2)
        local u = math.min(w, h)
        Draw.card(bb, m, m, w - 2 * m, h - 2 * m, o.roll and o.roll.winner)
        local plate_h = clamp(u * 0.12, s(26), s(34))
        local plate_face = Draw.face("bold", plate_h * 0.52)
        local name = p.name
        local px, py = m + s(14), m + s(14)
        local chip_h = clamp(u * 0.11, s(24), s(32))
        local reserve = math.max(py + plate_h, m + s(14) + chip_h)
        local cy = h / 2
        -- Commander damage by seat, in the top right corner: the table as this player sees it. It takes the
        -- larger of two free spaces, beside the life total (above the + mark, clear of a pending change)
        -- or above it, measured with a two-digit total so it does not change size as life goes up and down.
        local map_w, map_h = 0, 0
        local show_map = o.map and match:rules().commander_damage and not p.out and not o.roll
        if show_map then
            local ref = math.min((h - 2 * reserve) * 0.82, w * 0.46)
            local ref_w = Draw.text_width("88", Draw.face("serif", ref))
            local right = w - m - s(14)
            local most = clamp(u * 0.42, s(44), s(150))
            local aw, ah = TableMap.fit(o.map, p.seat, right - (w / 2 + ref_w / 2 + ref * 0.62) - s(6), math.min(most, cy - ref * 0.11 - py - s(8)))
            local bw2, bh2 = TableMap.fit(o.map, p.seat, w * 0.4, math.min(most, cy - ref * 0.45 - py - s(6)))
            if aw * ah >= bw2 * bh2 then
                map_w, map_h = aw, ah
            else
                map_w, map_h = bw2, bh2
            end
            show_map = map_h >= s(30)
        end
        local badges = {}
        if match.states.monarch == i then
            badges[#badges + 1] = "crown"
        end
        if match.states.initiative == i then
            badges[#badges + 1] = "star"
        end
        local right = w - m - s(14) - (show_map and (map_w + s(10)) or 0)
        local pw = math.max(plate_h * 2, math.min(Draw.text_width(name, plate_face) + plate_h * 1.6, w * 0.6, right - px))
        Draw.pill(bb, px, py, pw, plate_h, Draw.INK)
        Draw.icon(bb, "heart", px + plate_h * 0.55, py + plate_h / 2, plate_h * 0.42, Draw.WHITE)
        Draw.text(bb, name, plate_face, px + plate_h * 0.95, py, pw - plate_h * 1.2, plate_h, "left", Draw.WHITE)
        -- Under the name: the corner on the right holds the map, and the middle of a side block's top edge
        -- is where the round menu button sits.
        for b, icon in ipairs(badges) do
            Draw.icon(bb, icon, px + plate_h * 0.5 + (b - 1) * plate_h * 1.1, py + plate_h * 1.65, plate_h * 0.9, Draw.BLACK)
        end
        if o.roll then
            local size = math.min(h - 2 * reserve - s(16), w * 0.45)
            Draw.picture(bb, "art/d20.png", w / 2, cy, size, size)
            if not o.roll.winner then
                bb:lightenRect(math.floor(w / 2 - size / 2), math.floor(cy - size / 2), math.floor(size), math.floor(size), 0.45)
            end
            Draw.text(bb, tostring(o.roll.value), Draw.face("serif", size * 0.17), w / 2 - size / 2, cy - size * 0.08, size, size * 0.3, "center", Draw.BLACK)
            if o.roll.winner then
                local face = Draw.face("bold", chip_h * 0.6)
                local rw = Draw.text_width(t.wins_roll, face) + chip_h * 1.2
                Draw.pill(bb, w / 2 - rw / 2, h - m - s(14) - chip_h, rw, chip_h, Draw.INK)
                Draw.text(bb, t.wins_roll, face, w / 2 - rw / 2, h - m - s(14) - chip_h, rw, chip_h, "center", Draw.WHITE)
            end
            return
        end
        local pending = o.pending or 0
        local life = (p.life or 0) + pending
        local digits = #tostring(life)
        local size = math.min((h - 2 * reserve) * 0.82, w * (digits <= 2 and 0.46 or (digits == 3 and 0.34 or 0.26)))
        local ink = p.out and Draw.LIGHT or Draw.BLACK
        local sign = p.out and Draw.PALE or Draw.LIGHT
        local number_face = Draw.face("serif", size)
        local lw = Draw.text_width(tostring(life), number_face)
        -- Touch: left half takes life, right half gives; a hold moves 10.
        ctx:hit(0, 0, w / 2, h, function() o.on_change(-1) end, function() o.on_change(-10) end)
        ctx:hit(w / 2, 0, w / 2, h, function() o.on_change(1) end, function() o.on_change(10) end)
        Draw.text(bb, tostring(life), number_face, 0, cy - size * 0.6, w, size * 1.2, "center", ink)
        ctx:hit(w / 2 - lw / 2, cy - size * 0.45, lw, size * 0.9, function() o.on_keypad() end)
        local mark = size * 0.11
        Draw.hline(bb, w * 0.1 - mark, cy - math.max(1, size * 0.018), 2 * mark, math.max(2, size * 0.035), sign)
        Draw.hline(bb, w * 0.9 - mark, cy - math.max(1, size * 0.018), 2 * mark, math.max(2, size * 0.035), sign)
        bb:paintRect(math.floor(w * 0.9 - math.max(1, size * 0.018)), math.floor(cy - mark), math.max(2, math.floor(size * 0.035)), math.floor(2 * mark), sign)
        if pending ~= 0 then
            local label = pending > 0 and ("+" .. pending) or tostring(pending)
            local bf = Draw.face("bold", size * 0.24)
            local bh = size * 0.34
            local bw2 = Draw.text_width(label, bf) + size * 0.2
            local bx = math.min(w / 2 + lw / 2 + s(4), w - m - s(14) - bw2)
            local by = cy - size * 0.55
            Draw.pill(bb, bx, by, bw2, bh, Draw.INK)
            Draw.text(bb, label, bf, bx, by, bw2, bh, "center", Draw.WHITE)
        end
        local strip_y = h - m - s(14) - chip_h
        if p.out then
            local face = Draw.face("bold", chip_h * 0.6)
            local label = p.out_reason == "concede" and t.conceded or t.out
            local rw = Draw.text_width(label, face) + chip_h * 1.2
            Draw.pill(bb, w / 2 - rw / 2, strip_y, rw, chip_h, Draw.DARK)
            Draw.text(bb, label, face, w / 2 - rw / 2, strip_y, rw, chip_h, "center", Draw.WHITE)
        else
            local chips = magic_chips(o)
            if #chips > 0 then
                local face = Draw.face("bold", chip_h * 0.5)
                local widths, total = {}, 0
                local room = w - 2 * (m + s(14))
                local shown = 0
                for c, chip in ipairs(chips) do
                    widths[c] = Draw.chip(bb, 0, 0, chip_h, chip.icon, chip.text, { face = face, measure = true })
                    if total + widths[c] + (c > 1 and s(6) or 0) > room - (c < #chips and chip_h * 1.6 or 0) then
                        break
                    end
                    total = total + widths[c] + (c > 1 and s(6) or 0)
                    shown = c
                end
                local more = #chips - shown
                local more_label = "+" .. more
                if more > 0 then
                    total = total + s(6) + Draw.chip(bb, 0, 0, chip_h, nil, more_label, { face = face, measure = true })
                end
                local x = w / 2 - total / 2
                for c = 1, shown do
                    x = x + Draw.chip(bb, x, strip_y + chip_h / 2, chip_h, chips[c].icon, chips[c].text, { face = face }) + s(6)
                end
                if more > 0 then
                    Draw.chip(bb, x, strip_y + chip_h / 2, chip_h, nil, more_label, { face = face })
                end
            end
        end
        ctx:hit(m, strip_y - s(4), w - 2 * m, chip_h + s(8), function() o.on_markers() end)
        ctx:hit(px - s(6), py - s(6), pw + s(12), plate_h + s(12), function() o.on_menu() end)
        if show_map then
            local mx = w - m - s(14) - map_w
            TableMap.draw_small(bb, { map = o.map, seat = p.seat, match = match, i = i, x = mx, y = py, w = map_w, h = map_h })
            ctx:hit(mx - s(6), py - s(6), map_w + s(12), map_h + s(12), function() o.on_commander() end)
        end
    end }
end

---------------------------------------------------------------------------
-- Pokémon
---------------------------------------------------------------------------

local EXCLUSIVE = { { "sleep", "sleep" }, { "confusion", "spiral" }, { "paralysis", "bolt" } }
local REMINDERS = { "energy", "supporter", "retreat", "stadium" }

-- opts: match, i, t, on_reminder(key), on_coin(), on_condition(key), on_poison(delta), on_clear(),
-- on_end_turn(), on_menu().
function Blocks.pokemon(o)
    return { draw = function(_, ctx)
        local bb, w, h = ctx.bb, ctx.w, ctx.h
        local match, i, t = o.match, o.i, o.t
        local p = match.players[i]
        local mine = match.current == i
        -- Designed for 584 x 359 and scaled to the block.
        local k = math.min(w / 584, h / 359)
        local function K(v)
            return math.floor(v * k + 0.5)
        end
        local ox = math.floor((w - 584 * k) / 2)
        local oy = math.floor((h - 359 * k) / 2)
        local function X(v)
            return ox + K(v)
        end
        local function Y(v)
            return oy + K(v)
        end
        local m = s(2)
        Draw.card(bb, m, m, w - 2 * m, h - 2 * m, mine)
        local pf = Draw.face("bold", K(16))
        local pw = Draw.text_width(p.name, pf) + K(36)
        Draw.pill(bb, X(20), Y(16), pw, K(30), Draw.INK)
        Draw.text(bb, p.name, pf, X(20), Y(16), pw, K(30), "center", Draw.WHITE)
        ctx:hit(X(14), Y(10), pw + K(12), K(42), function() o.on_menu() end)
        if mine then
            Draw.pill(bb, X(454), Y(18), K(110), K(26), Draw.WHITE, Draw.BLACK, K(2))
            Draw.text(bb, t.your_turn, Draw.face("bold", K(14)), X(454), Y(18), K(110), K(26), "center")
        else
            Draw.text(bb, t.waiting, Draw.face("sans", K(14)), X(300), Y(16), K(264), K(30), "right", Draw.MID)
        end

        local tile_w = (544 - 3 * 8) / 4
        local rf = Draw.face("bold", K(15))
        for r, key in ipairs(REMINDERS) do
            local x0 = 20 + (r - 1) * (tile_w + 8)
            local label = t.reminders[key]
            if mine then
                local done = p.reminders[key]
                Draw.rect(bb, X(x0), Y(58), K(tile_w), K(38), done and Draw.INK or Draw.PAPER, K(10))
                Draw.border(bb, X(x0), Y(58), K(tile_w), K(38), K(1.5), Draw.BLACK, K(10))
                local bx = x0 + 12
                Draw.rect(bb, X(bx), Y(69), K(16), K(16), Draw.WHITE, K(3))
                if not done then
                    Draw.border(bb, X(bx), Y(69), K(16), K(16), K(1.5), Draw.BLACK, K(3))
                else
                    Draw.icon(bb, "check", X(bx + 8), Y(77), K(14), Draw.BLACK)
                end
                Draw.text(bb, label, rf, X(bx + 24), Y(58), K(tile_w - 40), K(38), "left", done and Draw.WHITE or Draw.BLACK)
                ctx:hit(X(x0), Y(56), K(tile_w), K(42), function() o.on_reminder(key) end)
            else
                Draw.rect(bb, X(x0), Y(58), K(tile_w), K(38), Draw.WHITE, K(10))
                Draw.border(bb, X(x0), Y(58), K(tile_w), K(38), K(1.2), Draw.PALE, K(10))
                Draw.text(bb, label, rf, X(x0), Y(58), K(tile_w), K(38), "center", Draw.LIGHT)
            end
        end

        local ccx, ccy, cr = 96, 200, 50
        Draw.circle(bb, X(ccx + 3), Y(ccy + 4), K(cr), Draw.LIGHT)
        Draw.picture(bb, "art/coin_" .. (p.last_coin or "heads") .. ".png", X(ccx), Y(ccy), K(2 * cr), K(2 * cr))
        local caption = p.last_coin and string.format(t.last_coin, p.last_coin == "heads" and t.heads_lower or t.tails_lower) or t.tap_coin
        Draw.text(bb, caption, Draw.face("sans", K(13)), X(ccx - 80), Y(ccy + cr + 6), K(160), K(24), "center", Draw.DARK)
        ctx:hit(X(ccx - cr - 10), Y(ccy - cr - 10), K(2 * cr + 20), K(2 * cr + 44), function() o.on_coin() end)

        local px0 = 184
        Draw.text(bb, t.conditions_title, Draw.face("bold", K(12)), X(px0), Y(112), K(220), K(24), "left", Draw.DARK)
        local lf = Draw.face("bold", K(12))
        local lw = Draw.text_width(t.clear_conditions, lf) / k + 26
        Draw.pill(bb, X(564 - lw), Y(112), K(lw), K(24), Draw.WHITE, Draw.BLACK, K(1.2))
        Draw.text(bb, t.clear_conditions, lf, X(564 - lw), Y(112), K(lw), K(24), "center")
        ctx:hit(X(560 - lw), Y(106), K(lw + 8), K(36), function() o.on_clear() end)
        local col_w = (564 - px0 - 10) / 2
        local lx0, rx0 = px0, px0 + col_w + 10
        local cf = Draw.face("bold", K(14))
        local function chip(x0, y0, key, icon, on)
            Draw.pill(bb, X(x0), Y(y0), K(col_w), K(36), on and Draw.INK or Draw.WHITE, on and Draw.BLACK or Draw.LIGHT, K(1.5))
            Draw.icon(bb, icon, X(x0 + 20), Y(y0 + 18), K(18), on and Draw.WHITE or Draw.MID)
            Draw.text(bb, t.conditions[key], cf, X(x0 + 38), Y(y0), K(col_w - 70), K(36), "left", on and Draw.WHITE or Draw.DARK)
        end
        for r, entry in ipairs(EXCLUSIVE) do
            local key, icon = entry[1], entry[2]
            local y0 = 146 + (r - 1) * 42
            local on = p.conditions[key]
            chip(lx0, y0, key, icon, on)
            Draw.icon(bb, "hint_" .. key, X(lx0 + col_w - 22), Y(y0 + 18), K(24), on and Draw.WHITE or Draw.MID)
            ctx:hit(X(lx0), Y(y0 - 2), K(col_w), K(40), function() o.on_condition(key) end)
        end
        chip(rx0, 146, "burn", "flame", p.conditions.burn)
        ctx:hit(X(rx0), Y(144), K(col_w), K(40), function() o.on_condition("burn") end)
        if p.conditions.poison then
            local y0 = 188
            Draw.rect(bb, X(rx0), Y(y0), K(col_w), K(78), Draw.INK, K(18))
            Draw.icon(bb, "drop", X(rx0 + 20), Y(y0 + 18), K(18), Draw.WHITE)
            Draw.text(bb, t.conditions.poison, cf, X(rx0 + 38), Y(y0), K(col_w - 50), K(36), "left", Draw.WHITE)
            ctx:hit(X(rx0), Y(y0 - 2), K(col_w), K(38), function() o.on_condition("poison") end)
            local sy = y0 + 54
            Draw.pill(bb, X(rx0 + 10), Y(sy - 15), K(col_w - 20), K(30), Draw.WHITE)
            Draw.icon(bb, "chevron_left", X(rx0 + 28), Y(sy), K(16), Draw.BLACK)
            Draw.icon(bb, "chevron_right", X(rx0 + col_w - 28), Y(sy), K(16), Draw.BLACK)
            Draw.text(bb, string.format(t.damage, p.poison), Draw.face("bold", K(13)), X(rx0 + 40), Y(sy - 15), K(col_w - 80), K(30), "center")
            ctx:hit(X(rx0), Y(sy - 18), K(col_w / 2), K(36), function() o.on_poison(-1) end)
            ctx:hit(X(rx0 + col_w / 2), Y(sy - 18), K(col_w / 2), K(36), function() o.on_poison(1) end)
        else
            chip(rx0, 188, "poison", "drop", false)
            ctx:hit(X(rx0), Y(186), K(col_w), K(40), function() o.on_condition("poison") end)
        end
        local hints = {}
        if p.conditions.confusion then
            hints[#hints + 1] = t.confused_hint
        end
        if mine and match.turn == 1 then
            hints[#hints + 1] = t.first_turn_hint
        end
        for n, hint in ipairs(hints) do
            Draw.text(bb, hint, Draw.face("italic", K(14)), X(px0), Y(272 + (n - 1) * 20), K(380), K(20), "left", Draw.BLACK)
        end
        if mine then
            Draw.button(bb, X(20), Y(307), K(544), K(36), t.end_turn, "filled", K(17))
            ctx:hit(X(16), Y(303), K(552), K(48), function() o.on_end_turn() end)
        end
    end }
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local function clock_label(o)
    local match, t, text = o.match, o.t, o.text
    local left = match:minutes_left()
    local time = left and string.format(t.minutes_left, left) or text:duration(match:minutes())
    return time .. "  ·  " .. string.format(t.turn, match.turn)
end

-- The bar between two players face to face. opts: match, t, text, main ("dice" or "coins"),
-- on_menu, on_undo, on_clock, on_main.
function Blocks.bar(o)
    return { draw = function(_, ctx)
        local bb, w, h = ctx.bb, ctx.w, ctx.h
        local cy = h / 2
        local r = h / 2 - s(4)
        Draw.round_button(bb, s(32), cy, r, "menu")
        ctx:hit(0, 0, s(32) + r + s(6), h, o.on_menu)
        local ux = s(32) + 2 * r + s(14)
        Draw.round_button(bb, ux, cy, r, "undo", o.match:can_undo() and Draw.WHITE or Draw.MID)
        ctx:hit(ux - r - s(6), 0, 2 * r + s(12), h, o.on_undo)
        Draw.round_button(bb, w - s(32), cy, r, o.main == "coins" and "coins" or "d20")
        ctx:hit(w - s(32) - r - s(8), 0, r * 2 + s(16), h, o.on_main)
        local face = Draw.face("bold", s(17))
        local label = clock_label(o)
        local tw = Draw.text_width(label, face) + s(56)
        local x = w / 2 - tw / 2 + s(20)
        Draw.pill(bb, x, cy - r, tw, 2 * r, Draw.WHITE)
        Draw.icon(bb, "clock", x + s(24), cy, s(20))
        Draw.text(bb, label, face, x + s(40), cy - r, tw - s(48), 2 * r, "left")
        ctx:hit(x, 0, tw, h, o.on_clock)
    end }
end

-- The round menu button over the junction of the blocks.
function Blocks.hub(o)
    return { draw = function(_, ctx)
        local bb, w, h = ctx.bb, ctx.w, ctx.h
        local cx, cy = w / 2, h / 2
        local r = math.min(w, h) / 2 - s(8)
        Draw.circle(bb, cx, cy, r + s(4), Draw.INK)
        Draw.circle(bb, cx, cy, r, Draw.WHITE)
        Draw.circle(bb, cx, cy, r - s(5), Draw.INK)
        if o.play then
            Draw.icon(bb, "check", cx, cy, r * 0.95, Draw.WHITE)
        else
            Draw.icon(bb, "menu", cx, cy, r * 0.9, Draw.WHITE)
        end
        local state = o.match.states.day_night
        if state and not o.play then
            local bx, by = cx + r * 0.72, cy - r * 0.72
            Draw.circle(bb, bx, by, s(13), Draw.WHITE)
            Draw.ring(bb, bx, by, s(13), s(1.5), Draw.BLACK)
            Draw.icon(bb, state == "day" and "sun" or "moon", bx, by, s(18))
        end
        ctx:hit(0, 0, w, h, o.on_menu)
    end }
end

-- The empty cell of a grid, with the clock and the main buttons.
function Blocks.controls(o)
    return { draw = function(_, ctx)
        local bb, w, h = ctx.bb, ctx.w, ctx.h
        local t = o.t
        Draw.rect(bb, s(2), s(2), w - s(4), h - s(4), Draw.DARK, s(16))
        Draw.border(bb, s(8), s(8), w - s(16), h - s(16), 1, Draw.MID, s(12))
        local match = o.match
        local left = match:minutes_left()
        local time = left and string.format(t.minutes_left, left) or o.text:duration(match:minutes())
        Draw.icon(bb, "clock", w / 2 - Draw.text_width(time, Draw.face("bold", s(24))) / 2 - s(20), h * 0.16, s(22), Draw.WHITE)
        Draw.text(bb, time, Draw.face("bold", s(24)), s(8) + s(14), h * 0.16 - s(16), w - s(16), s(32), "center", Draw.WHITE)
        Draw.text(bb, string.format(t.turn, match.turn), Draw.face("sans", s(15)), 0, h * 0.16 + s(16), w, s(22), "center", Draw.LIGHT)
        ctx:hit(0, 0, w, h * 0.32, o.on_clock)
        local buttons = {
            { "menu", t.menu_title, o.on_menu },
            { "undo", t.undo, o.on_undo },
            { "d20", t.dice, o.on_dice },
            { "coins", t.coins, o.on_coins },
        }
        local r = math.min(s(26), w * 0.11, h * 0.09)
        for b, entry in ipairs(buttons) do
            local col, row = (b - 1) % 2, math.floor((b - 1) / 2)
            local cx = w / 2 + (col == 0 and -1 or 1) * w * 0.2
            local cy = h * 0.5 + row * h * 0.26
            Draw.round_button(bb, cx, cy, r, entry[1])
            Draw.text(bb, entry[2], Draw.face("sans", s(12)), cx - w * 0.2, cy + r + s(2), w * 0.4, s(18), "center", Draw.LIGHT)
            ctx:hit(cx - w * 0.2, cy - r - s(6), w * 0.4, 2 * r + s(28), entry[3])
        end
    end }
end

return Blocks
