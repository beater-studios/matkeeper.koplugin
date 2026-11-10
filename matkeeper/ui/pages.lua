local Draw = require("matkeeper/ui/draw")
local Layouts = require("matkeeper/layouts")

-- Full screen pages around the table: home, the setup steps, past matches, a match log and settings.
local Pages = {}

local s = Draw.s

local function header(ctx, title_text, subtitle, on_back, step, steps, t)
    local bb, w = ctx.bb, ctx.w
    local hh = s((step ~= nil) and 132 or 112)
    Draw.rect(bb, 0, 0, w, hh, Draw.INK)
    Draw.picture(bb, "art/header.png", w / 2, hh / 2, w, hh)
    Draw.rect(bb, 0, hh - s(6), w, s(6), Draw.BLACK)
    Draw.circle(bb, s(42), s(50), s(22), Draw.WHITE)
    Draw.icon(bb, "chevron_left", s(40), s(50), s(22))
    ctx:hit(0, 0, s(90), s(96), on_back)
    Draw.text(bb, title_text, Draw.face("serif", s(29)), s(78), s(30), w - s(100), s(40), "left", Draw.WHITE)
    if step and steps then
        for i = 1, steps do
            local x = s(82) + (i - 1) * s(22)
            if i == step then
                Draw.rect(bb, x - s(2), s(92), s(20), s(10), Draw.WHITE, s(5))
            else
                Draw.circle(bb, x + s(5), s(97), s(4), Draw.MID)
            end
        end
        Draw.text(bb, string.format(t.step, step, steps), Draw.face("sans", s(14)), s(82) + steps * s(22) + s(6), s(86), s(200), s(22), "left", Draw.LIGHT)
    elseif subtitle then
        Draw.text(bb, subtitle, Draw.face("sans", s(15)), s(80), s(72), w - s(100), s(24), "left", Draw.LIGHT)
    end
    return hh
end

local function footer(ctx, primary, on_primary, secondary, on_secondary, enabled)
    local bb, w, h = ctx.bb, ctx.w, ctx.h
    Draw.rect(bb, 0, h - s(92), w, s(92), Draw.PAPER)
    Draw.hline(bb, 0, h - s(92), w, 1, Draw.LIGHT)
    local style = enabled == false and "disabled" or "filled"
    if secondary then
        local half = (w - s(48) - s(28)) / 2
        Draw.button(bb, s(24), h - s(70), half, s(48), secondary, "outline", s(16))
        ctx:hit(s(24), h - s(74), half, s(56), on_secondary)
        Draw.button(bb, s(24) + half + s(28), h - s(70), half, s(48), primary, style, s(16))
        if enabled ~= false then
            ctx:hit(s(24) + half + s(28), h - s(74), half, s(56), on_primary)
        end
    else
        Draw.button(bb, s(24), h - s(70), w - s(48), s(48), primary, style, s(18))
        if enabled ~= false then
            ctx:hit(s(24), h - s(74), w - s(48), s(56), on_primary)
        end
    end
end

local function page_footer(ctx, page, pages, t, on_page)
    local bb, w, h = ctx.bb, ctx.w, ctx.h
    if pages <= 1 then
        return
    end
    Draw.hline(bb, s(24), h - s(48), w - s(48), 1, Draw.PALE)
    Draw.icon(bb, "chevron_left", s(44), h - s(24), s(22), page > 1 and Draw.BLACK or Draw.PALE)
    Draw.icon(bb, "chevron_right", w - s(44), h - s(24), s(22), page < pages and Draw.BLACK or Draw.PALE)
    Draw.text(bb, string.format(t.page, page, pages), Draw.face("sans", s(15)), 0, h - s(40), w, s(32), "center", Draw.DARK)
    ctx:hit(0, h - s(56), w / 3, s(56), function()
        if page > 1 then
            on_page(page - 1)
        end
    end)
    ctx:hit(w * 2 / 3, h - s(56), w / 3, s(56), function()
        if page < pages then
            on_page(page + 1)
        end
    end)
end

local function logo(bb, game, cx, cy, size)
    local box = size == "large" and { 220, 150 } or { 112, 60 }
    Draw.picture(bb, "logos/" .. game .. "_" .. size .. ".png", cx, cy, s(box[1]), s(box[2]))
end

-- opts: t, text, saved (match or nil), last (setup or nil), name, on_continue, on_new, on_repeat,
-- on_history, on_settings, on_close.
function Pages.home(o)
    return { draw = function(_, ctx)
        local bb, w, h, t = ctx.bb, ctx.w, ctx.h, o.t
        Draw.rect(bb, 0, 0, w, h, Draw.WHITE)
        local bh = s(300)
        Draw.rect(bb, 0, 0, w, bh, Draw.INK)
        Draw.picture(bb, "art/banner.png", w / 2, s(147), w, s(294))
        Draw.rect(bb, 0, bh - s(6), w, s(6), Draw.BLACK)
        Draw.circle(bb, s(42), s(46), s(22), Draw.WHITE)
        Draw.icon(bb, "chevron_left", s(40), s(46), s(22))
        ctx:hit(0, 0, s(90), s(90), o.on_close)
        Draw.text(bb, o.name, Draw.face("serif", s(34)), 0, s(232), w, s(46), "center", Draw.WHITE)
        local y = s(330)
        local saved = o.saved
        if saved then
            local ch = s(190)
            Draw.rect(bb, s(28), y + s(5), w - s(48), ch, Draw.LIGHT, s(16))
            Draw.rect(bb, s(24), y, w - s(48), ch, Draw.WHITE, s(16))
            Draw.border(bb, s(24), y, w - s(48), ch, s(3), Draw.BLACK, s(16))
            Draw.text(bb, t.continue_match_label, Draw.face("bold", s(15)), s(46), y + s(18), w, s(24), "left", Draw.DARK)
            logo(bb, saved.game, s(96), y + s(96), "small")
            local fmt = t.formats[saved.format]
            Draw.text(bb, fmt, Draw.face("serif", s(26)), s(170), y + s(48), w - s(250), s(36), "left")
            Draw.text(bb, string.format(t.match_line, #saved.players, saved.turn, o.text:duration(saved:minutes())), Draw.face("sans", s(16)), s(170), y + s(84), w - s(250), s(26), "left", Draw.DARK)
            local x = s(170)
            local count = math.min(#saved.players, 4)
            local col = (w - s(250)) / count
            for i = 1, count do
                local p = saved.players[i]
                Draw.text(bb, p.name, Draw.face("sans", s(13)), x, y + s(118), col - s(6), s(20), "left", Draw.DARK)
                local value = saved:kind() == "score" and tostring(p.life) or (saved.current == i and t.your_turn or "")
                Draw.text(bb, value, Draw.face("serif", s(saved:kind() == "score" and 22 or 14)), x, y + s(140), col - s(6), s(30), "left")
                x = x + col
            end
            Draw.circle(bb, w - s(56), y + s(95), s(20), Draw.INK)
            Draw.icon(bb, "chevron_right", w - s(54), y + s(95), s(20), Draw.WHITE)
            ctx:hit(s(24), y, w - s(48), ch, o.on_continue)
            y = y + ch + s(40)
        end
        Draw.button(bb, s(24), y, w - s(48), s(56), t.new_match, "filled", s(20))
        ctx:hit(s(24), y - s(4), w - s(48), s(64), o.on_new)
        y = y + s(76)
        if o.last then
            Draw.rect(bb, s(24), y, w - s(48), s(80), Draw.WHITE, s(16))
            Draw.border(bb, s(24), y, w - s(48), s(80), s(2), Draw.BLACK, s(16))
            Draw.text(bb, t.repeat_last, Draw.face("bold", s(19)), s(48), y + s(10), w - s(150), s(30), "left")
            local line = string.format(t.repeat_line, t.formats[o.last.format] .. " · " .. t.games_short[o.last.game], #o.last.seats)
            Draw.text(bb, line, Draw.face("sans", s(15)), s(48), y + s(42), w - s(150), s(26), "left", Draw.DARK)
            Draw.icon(bb, "rotate", w - s(58), y + s(40), s(30))
            ctx:hit(s(24), y, w - s(48), s(80), o.on_repeat)
            y = y + s(100)
        end
        local face = Draw.face("sans", s(16))
        local links = { { t.history, o.on_history }, { t.settings, o.on_settings } }
        local ly = math.max(y, h - s(60))
        for l, link in ipairs(links) do
            local cx = w * (l == 1 and 0.32 or 0.72)
            local tw = Draw.text_width(link[1], face)
            Draw.text(bb, link[1], face, cx - tw / 2 - s(4), ly, tw + s(8), s(28), "center", Draw.DARK)
            Draw.hline(bb, cx - tw / 2, ly + s(28), tw, 1, Draw.MID)
            ctx:hit(cx - tw / 2 - s(20), ly - s(10), tw + s(40), s(50), link[2])
        end
    end }
end

-- Step 1: the game. opts: t, games (ids), selected, on_pick(id), on_continue, on_back, step, steps.
function Pages.game(o)
    return { draw = function(_, ctx)
        local bb, w, h, t = ctx.bb, ctx.w, ctx.h, o.t
        Draw.rect(bb, 0, 0, w, h, Draw.WHITE)
        header(ctx, t.step_game, nil, o.on_back, o.step, o.steps, t)
        local cw = (w - s(48) - s(12)) / 2
        for g, id in ipairs(o.games) do
            local x0 = s(24) + (g - 1) * (cw + s(12))
            local y0 = s(190)
            local ch = s(370)
            local selected = o.selected == id
            Draw.rect(bb, x0 + s(4), y0 + s(5), cw, ch, Draw.LIGHT, s(18))
            Draw.rect(bb, x0, y0, cw, ch, Draw.WHITE, s(18))
            Draw.border(bb, x0, y0, cw, ch, selected and s(4) or s(2), Draw.BLACK, s(18))
            Draw.border(bb, x0 + s(14), y0 + s(14), cw - s(28), s(240), s(1.5), Draw.PALE, s(12))
            logo(bb, id, x0 + cw / 2, y0 + s(134), "large")
            local name = t.games[id]
            Draw.text(bb, name, Draw.face("serif", #name > 14 and s(19) or s(24)), x0 + s(8), y0 + s(272), cw - s(16), s(36), "center")
            Draw.text(bb, t.game_players[id], Draw.face("sans", s(16)), x0, y0 + s(312), cw, s(26), "center", Draw.DARK)
            if selected then
                Draw.check_badge(bb, x0 + cw - s(8), y0 + s(8), s(20))
            end
            ctx:hit(x0, y0, cw, ch, function() o.on_pick(id) end)
        end
        Draw.text(bb, t.other_games, Draw.face("sans", s(15)), 0, s(596), w, s(28), "center", Draw.MID)
        footer(ctx, t.continue, o.on_continue, nil, nil, o.selected ~= nil)
    end }
end

-- Step 2: the format. opts: t, game, formats, selected, life_of(format), on_pick(id), on_continue, on_back.
function Pages.format(o)
    return { draw = function(_, ctx)
        local bb, w, h, t = ctx.bb, ctx.w, ctx.h, o.t
        Draw.rect(bb, 0, 0, w, h, Draw.WHITE)
        header(ctx, t.step_format, nil, o.on_back, o.step, o.steps, t)
        Draw.text(bb, t.games[o.game], Draw.face("sans", s(18)), s(30), s(150), w, s(30), "left", Draw.DARK)
        local y = s(190)
        local count = #o.formats
        local gap = s(12)
        local ch = math.min(s(104), math.floor((h - s(92) - s(16) - y - (count - 1) * gap) / count))
        local title_face = Draw.face("serif", ch < s(96) and s(22) or s(24))
        for _, format in ipairs(o.formats) do
            local selected = o.selected == format.id
            Draw.rect(bb, s(24), y, w - s(48), ch, Draw.WHITE, s(14))
            Draw.border(bb, s(24), y, w - s(48), ch, selected and s(4) or s(1.5), Draw.BLACK, s(14))
            if selected then
                Draw.rect(bb, s(24), y, s(10), ch, Draw.INK, s(4))
            end
            Draw.text(bb, t.formats[format.id], title_face, s(52), y + ch * 0.16, w - s(220), s(36), "left")
            Draw.text(bb, t.format_info[o.game][format.id], Draw.face("sans", s(15)), s(52), y + ch * 0.56, w - s(220), s(28), "left", Draw.DARK)
            local life = o.life_of(format)
            if life then
                bb:paintRect(w - s(140), y + s(16), math.max(1, s(1.5)), ch - s(32), Draw.PALE)
                Draw.icon(bb, "heart", w - s(112), y + ch / 2, s(22), Draw.DARK)
                Draw.text(bb, tostring(life), Draw.face("serif", s(38)), w - s(100), y + ch / 2 - s(26), s(52), s(52), "right")
            end
            ctx:hit(s(24), y, w - s(48), ch, function() o.on_pick(format.id) end)
            y = y + ch + gap
        end
        footer(ctx, t.continue, o.on_continue, nil, nil, o.selected ~= nil)
    end }
end

local function step_button(ctx, cx, cy, r, plus, on_tap, on_hold)
    local bb = ctx.bb
    Draw.circle(bb, cx + s(2), cy + s(3), r, Draw.LIGHT)
    Draw.circle(bb, cx, cy, r, Draw.WHITE)
    Draw.ring(bb, cx, cy, r, s(3), Draw.BLACK)
    local arm = math.floor(r * 0.45)
    local thick = math.max(2, s(4))
    bb:paintRect(math.floor(cx - arm), math.floor(cy - thick / 2), 2 * arm, thick, Draw.BLACK)
    if plus then
        bb:paintRect(math.floor(cx - thick / 2), math.floor(cy - arm), thick, 2 * arm, Draw.BLACK)
    end
    ctx:hit(cx - r - s(14), cy - r - s(14), 2 * r + s(28), 2 * r + s(28), on_tap, on_hold)
end

local function toggle_row(ctx, x, y, w, h, label, on, on_tap)
    local bb = ctx.bb
    Draw.rect(bb, x, y, w, h, Draw.WHITE, s(14))
    Draw.border(bb, x, y, w, h, on and s(3) or s(1.5), Draw.BLACK, s(14))
    Draw.text(bb, label, Draw.face("bold", s(17)), x + s(20), y, w - s(120), h, "left")
    local tw, th = s(60), s(32)
    local tx, ty = x + w - s(20) - tw, y + (h - th) / 2
    Draw.pill(bb, tx, ty, tw, th, on and Draw.INK or Draw.PALE)
    Draw.circle(bb, on and (tx + tw - th / 2) or (tx + th / 2), ty + th / 2, th / 2 - s(4), Draw.WHITE)
    ctx:hit(x, y, w, h, on_tap)
end

-- Step 3 of a custom match: its rules. opts: t, rules, presets, on_life(delta), on_preset(v),
-- on_toggle(name), on_continue, on_back, step, steps.
function Pages.rules(o)
    return { draw = function(_, ctx)
        local bb, w, h, t, r = ctx.bb, ctx.w, ctx.h, o.t, o.rules
        Draw.rect(bb, 0, 0, w, h, Draw.WHITE)
        header(ctx, t.step_rules, nil, o.on_back, o.step, o.steps, t)
        Draw.text(bb, t.rules_hint, Draw.face("sans", s(15)), s(30), s(146), w - s(60), s(28), "left", Draw.DARK)
        local x0, y0, cw, ch = s(24), s(188), w - s(48), s(262)
        Draw.rect(bb, x0 + s(4), y0 + s(5), cw, ch, Draw.LIGHT, s(18))
        Draw.rect(bb, x0, y0, cw, ch, Draw.WHITE, s(18))
        Draw.border(bb, x0, y0, cw, ch, s(3), Draw.BLACK, s(18))
        Draw.icon(bb, "heart", x0 + s(34), y0 + s(30), s(22), Draw.DARK)
        Draw.text(bb, t.rules_life, Draw.face("bold", s(17)), x0 + s(54), y0 + s(16), cw - s(80), s(28), "left")
        local cy = y0 + s(104)
        Draw.text(bb, tostring(r.life), Draw.face("serif", s(78)), x0 + s(110), cy - s(48), cw - s(220), s(96), "center")
        step_button(ctx, x0 + s(62), cy, s(32), false, function() o.on_life(-1) end, function() o.on_life(-10) end)
        step_button(ctx, x0 + cw - s(62), cy, s(32), true, function() o.on_life(1) end, function() o.on_life(10) end)
        local n = #o.presets
        local pw, pg = s(84), s(14)
        local px = x0 + (cw - n * pw - (n - 1) * pg) / 2
        local py = y0 + s(166)
        for _, v in ipairs(o.presets) do
            local on = v == r.life
            Draw.pill(bb, px, py, pw, s(42), on and Draw.INK or Draw.WHITE, (not on) and Draw.BLACK or nil, s(1.5))
            Draw.text(bb, tostring(v), Draw.face("bold", s(19)), px, py, pw, s(42), "center", on and Draw.WHITE or Draw.BLACK)
            ctx:hit(px - pg / 2, py - s(6), pw + pg, s(54), function() o.on_preset(v) end)
            px = px + pw + pg
        end
        Draw.text(bb, t.rules_life_hint, Draw.face("sans", s(14)), x0, y0 + s(220), cw, s(26), "center", Draw.MID)
        local y = y0 + ch + s(22)
        for _, item in ipairs({ { "poison", t.rules_poison }, { "commander", t.rules_commander }, { "tax", t.rules_tax } }) do
            toggle_row(ctx, s(24), y, w - s(48), s(58), item[2], r[item[1]], function() o.on_toggle(item[1]) end)
            y = y + s(70)
        end
        footer(ctx, t.continue, o.on_continue)
    end }
end

-- Step 3: how many players. opts: t, min, max, selected, format_name, teams, on_pick(n), on_continue, on_back.
function Pages.players(o)
    return { draw = function(_, ctx)
        local bb, w, h, t = ctx.bb, ctx.w, ctx.h, o.t
        Draw.rect(bb, 0, 0, w, h, Draw.WHITE)
        header(ctx, t.step_players, nil, o.on_back, o.step, o.steps, t)
        Draw.text(bb, string.format(t.players_range, o.format_name, o.min, o.max), Draw.face("sans", s(18)), s(30), s(150), w, s(30), "left", Draw.DARK)
        local count = o.max - o.min + 1
        local gap = (w - s(60)) / math.max(count, 5)
        for n = o.min, o.max do
            local cx = s(30) + gap * (n - o.min) + gap / 2
            local selected = n == o.selected
            Draw.circle(bb, cx + s(3), s(268), s(42), Draw.LIGHT)
            Draw.circle(bb, cx, s(264), s(42), selected and Draw.INK or Draw.WHITE)
            Draw.ring(bb, cx, s(264), s(42), s(3), Draw.BLACK)
            Draw.text(bb, tostring(n), Draw.face("serif", s(40)), cx - s(40), s(234), s(80), s(60), "center", selected and Draw.WHITE or Draw.BLACK)
            ctx:hit(cx - gap / 2, s(214), gap, s(100), function() o.on_pick(n) end)
        end
        if o.selected then
            Draw.text(bb, string.format(t.preview, o.selected), Draw.face("sans", s(15)), 0, s(348), w, s(24), "center", Draw.DARK)
            local layout = Layouts.for_players(o.selected, w, h)[1]
            local px0, py0, pw, ph = s(150), s(384), s(300), s(300)
            Draw.rect(bb, px0, py0, pw, ph, Draw.INK, s(14))
            for _, cell in ipairs(Layouts.rects(layout, px0 + s(8), py0 + s(8), pw - s(16), ph - s(16), s(6))) do
                Draw.rect(bb, cell.x, cell.y, cell.w, cell.h, cell.kind == "p" and Draw.WHITE or Draw.DARK, s(8))
            end
        end
        footer(ctx, t.continue, o.on_continue, nil, nil, o.selected ~= nil)
    end }
end

local ARROW = { bottom = { 0, 1 }, top = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

local function mini(ctx, layout, x0, y0, w, h, selected)
    local bb = ctx.bb
    Draw.rect(bb, x0 + s(3), y0 + s(4), w, h, Draw.LIGHT, s(14))
    Draw.rect(bb, x0, y0, w, h, Draw.INK, s(14))
    if selected then
        Draw.border(bb, x0, y0, w, h, s(5), Draw.BLACK, s(14))
    end
    local seats = Layouts.suggested_seats(layout)
    local k = 0
    for _, cell in ipairs(Layouts.rects(layout, x0 + s(10), y0 + s(10), w - s(20), h - s(20), s(6))) do
        if cell.kind == "e" then
            Draw.rect(bb, cell.x, cell.y, cell.w, cell.h, Draw.DARK, s(8))
            Draw.icon(bb, "menu", cell.x + cell.w / 2, cell.y + cell.h / 2, s(22), Draw.LIGHT)
        else
            k = k + 1
            Draw.rect(bb, cell.x, cell.y, cell.w, cell.h, Draw.WHITE, s(8))
            local seat = seats[k]
            local dx, dy = ARROW[seat][1], ARROW[seat][2]
            local mx, my = cell.x + cell.w / 2, cell.y + cell.h / 2
            local reach = math.min(cell.w, cell.h) * 0.28
            Draw.icon_turned(bb, "triangle", mx + dx * reach, my + dy * reach, s(22), Draw.DARK, Layouts.degrees(seat))
            Draw.text(bb, tostring(k), Draw.face("serif", s(22)), mx - dx * reach * 0.4 - s(20), my - dy * reach * 0.4 - s(16), s(40), s(32), "center", Draw.MID)
        end
    end
    if selected then
        Draw.check_badge(bb, x0 + w - s(6), y0 + s(6), s(18))
    end
end

-- Step 4: the layout. opts: t, count, layouts, selected (id), page, on_pick(id), on_page, on_continue, on_back.
function Pages.layouts(o)
    return { draw = function(_, ctx)
        local bb, w, h, t = ctx.bb, ctx.w, ctx.h, o.t
        Draw.rect(bb, 0, 0, w, h, Draw.WHITE)
        header(ctx, t.step_layout, nil, o.on_back, o.step, o.steps, t)
        Draw.text(bb, string.format(t.layout_hint, o.count), Draw.face("sans", s(16)), s(30), s(146), w - s(40), s(30), "left", Draw.DARK)
        local per_page = 4
        local pages = math.ceil(#o.layouts / per_page)
        local page = math.max(1, math.min(o.page or 1, pages))
        local mw = (w - s(60) - s(24)) / 2
        local mh = math.min(s(250), (h - s(190) - s(150)) / 2 - s(16))
        for idx = (page - 1) * per_page + 1, math.min(#o.layouts, page * per_page) do
            local pos = idx - (page - 1) * per_page - 1
            local col, row = pos % 2, math.floor(pos / 2)
            local x0 = s(30) + col * (mw + s(24))
            local y0 = s(186) + row * (mh + s(22))
            local layout = o.layouts[idx]
            mini(ctx, layout, x0, y0, mw, mh, layout.id == o.selected)
            ctx:hit(x0, y0, mw, mh, function() o.on_pick(layout.id) end)
        end
        if pages > 1 then
            local py = h - s(140)
            Draw.text(bb, string.format(t.page, page, pages), Draw.face("sans", s(15)), 0, py, w, s(36), "center", Draw.DARK)
            Draw.icon(bb, "chevron_left", s(60), py + s(18), s(24), page > 1 and Draw.BLACK or Draw.PALE)
            Draw.icon(bb, "chevron_right", w - s(60), py + s(18), s(24), page < pages and Draw.BLACK or Draw.PALE)
            ctx:hit(0, py - s(10), w / 3, s(56), function()
                if page > 1 then
                    o.on_page(page - 1)
                end
            end)
            ctx:hit(w * 2 / 3, py - s(10), w / 3, s(56), function()
                if page < pages then
                    o.on_page(page + 1)
                end
            end)
        end
        footer(ctx, t.continue, o.on_continue, nil, nil, o.selected ~= nil)
    end }
end

-- A seat in the preview of step 5, drawn in its owner's orientation. The rotate button sits at the
-- center, the one point that stays in place when the block turns, so it can be tapped again.
function Pages.seat_block(o)
    return { draw = function(_, ctx)
        local bb, w, h = ctx.bb, ctx.w, ctx.h
        Draw.card(bb, s(2), s(2), w - s(4), h - s(4))
        local u = math.min(w, h)
        local r = math.floor(math.min(s(26), u * 0.15))
        local cx, cy = w / 2, h / 2
        local nh = math.floor(math.min(s(34), h * 0.18))
        local tri = math.floor(math.min(s(22), h * 0.1))
        local below = h - (cy + r) - tri - s(8)
        local ny = cy + r + math.max(s(4), (below - nh) / 2)
        local face = Draw.face("bold", math.min(s(17), nh * 0.5))
        local nw = math.min(math.max(Draw.text_width(o.name, face) + s(40), s(110)), w - s(24))
        Draw.pill(bb, w / 2 - nw / 2, ny, nw, nh, Draw.WHITE, Draw.BLACK, s(1.5))
        Draw.text(bb, o.name, face, w / 2 - nw / 2 + s(10), ny, nw - s(20), nh, "center")
        ctx:hit(w / 2 - nw / 2 - s(10), ny - s(6), nw + s(20), nh + s(12), o.on_rename)
        local top = cy - r - s(6)
        if top > s(24) then
            Draw.text(bb, tostring(o.number), Draw.face("serif", math.min(top * 0.8, u * 0.3)), 0, s(4), w, top - s(4), "center", Draw.PALE)
        end
        Draw.icon(bb, "triangle", w / 2, h - tri / 2 - s(8), tri, Draw.INK)
        Draw.round_button(bb, cx, cy, r, "rotate", Draw.PAPER, Draw.BLACK, Draw.BLACK)
        ctx:hit(cx - r - s(10), cy - r - s(10), 2 * r + s(20), 2 * r + s(20), o.on_rotate)
    end }
end

-- Step 5 is built by the screen (it needs a pane per seat); this draws its frame around the preview.
function Pages.seats_frame(o)
    return { draw = function(_, ctx)
        local bb, w, h, t = ctx.bb, ctx.w, ctx.h, o.t
        Draw.rect(bb, 0, 0, w, h, Draw.WHITE)
        header(ctx, t.step_seats, nil, o.on_back, o.step, o.steps, t)
        Draw.text(bb, t.seats_hint, Draw.face("sans", s(15)), s(24), s(146), w - s(48), s(28), "left", Draw.DARK)
        local px, py, pw, ph = o.preview.x, o.preview.y, o.preview.w, o.preview.h
        Draw.rect(bb, px, py, pw, ph, Draw.INK, s(16))
        footer(ctx, t.start, o.on_start, t.draw_start, o.on_draw)
    end }
end

-- Past matches. opts: t, text, list, page, now, on_open(i), on_page, on_back.
function Pages.history(o)
    return { draw = function(_, ctx)
        local bb, w, h, t = ctx.bb, ctx.w, ctx.h, o.t
        Draw.rect(bb, 0, 0, w, h, Draw.WHITE)
        local top = header(ctx, t.history, nil, o.on_back)
        if #o.list == 0 then
            Draw.text(bb, t.no_history, Draw.face("sans", s(18)), 0, top + s(60), w, s(40), "center", Draw.DARK)
            return
        end
        local per_page = math.max(1, math.floor((h - top - s(80)) / s(146)))
        local pages = math.ceil(#o.list / per_page)
        local page = math.max(1, math.min(o.page or 1, pages))
        local y = top + s(24)
        for idx = (page - 1) * per_page + 1, math.min(#o.list, page * per_page) do
            local item = o.list[idx]
            Draw.rect(bb, s(24), y, w - s(48), s(132), Draw.WHITE, s(14))
            Draw.border(bb, s(24), y, w - s(48), s(132), s(1.5), Draw.BLACK, s(14))
            logo(bb, item.game, s(92), y + s(66), "small")
            Draw.text(bb, t.games_short[item.game] .. "  ·  " .. (t.formats[item.format] or ""), Draw.face("serif", s(21)), s(170), y + s(14), w - s(240), s(34), "left")
            Draw.text(bb, o.text:when(item.started, o.now) .. "  ·  " .. o.text:duration(item.minutes or 0), Draw.face("sans", s(15)), s(170), y + s(48), w - s(240), s(26), "left", Draw.DARK)
            Draw.text(bb, o.text:join(item.players), Draw.face("sans", s(15)), s(170), y + s(74), w - s(240), s(26), "left", Draw.DARK)
            local result, winner
            if item.winner then
                result, winner = string.format(t.won, item.players[item.winner] or "?"), true
            elseif item.draw then
                result = t.draw_result
            else
                result = t.no_winner_result
            end
            if winner then
                Draw.icon(bb, "crown", s(178), y + s(113), s(16))
            end
            Draw.text(bb, result, Draw.face("bold", s(14)), winner and s(192) or s(170), y + s(100), w - s(260), s(26), "left", (winner or item.draw) and Draw.BLACK or Draw.MID)
            Draw.icon(bb, "chevron_right", w - s(50), y + s(66), s(22), Draw.DARK)
            ctx:hit(s(24), y, w - s(48), s(132), function() o.on_open(idx) end)
            y = y + s(146)
        end
        page_footer(ctx, page, pages, t, o.on_page)
    end }
end

local LOG_ICONS = { coin = "coin", coins = "coin", ["until"] = "coin", call = "coin", condition = "drop", poison = "drop",
    clear = "check", checkup = "clock", life = "heart", counter = "drop", commander = "shield", tax = "shield",
    state = "crown", out = "menu", dice = "d20", roll_start = "d20", finish = "crown", starter = "check" }

-- A match log. opts: t, title, subtitle, lines, page, on_page, on_back.
function Pages.log(o)
    return { draw = function(_, ctx)
        local bb, w, h, t = ctx.bb, ctx.w, ctx.h, o.t
        Draw.rect(bb, 0, 0, w, h, Draw.WHITE)
        local top = header(ctx, o.title, o.subtitle, o.on_back)
        local face = Draw.face("sans", s(16))
        local line_h = s(22)
        local text_w = w - s(98)
        -- Lay the lines out into pages first.
        local pages, page_rows, used = {}, {}, 0
        local room = h - top - s(70)
        for _, line in ipairs(o.lines) do
            local rh, wrapped
            if line.heading then
                rh = s(36)
            else
                wrapped = Draw.wrap(line.text, face, text_w)
                rh = #wrapped * line_h + s(12)
            end
            if used + rh > room and #page_rows > 0 then
                pages[#pages + 1] = page_rows
                page_rows, used = {}, 0
            end
            page_rows[#page_rows + 1] = { line = line, wrapped = wrapped, h = rh }
            used = used + rh
        end
        if #page_rows > 0 then
            pages[#pages + 1] = page_rows
        end
        local page = math.max(1, math.min(o.page or 1, #pages))
        local y = top + s(20)
        for _, row in ipairs(pages[page] or {}) do
            local line = row.line
            if line.heading then
                local hf = Draw.face("bold", s(13))
                local label = line.heading:upper()
                local lw = Draw.text_width(label, hf)
                Draw.text(bb, label, hf, s(28), y + s(6), lw + s(4), s(24), "left", Draw.DARK)
                Draw.hline(bb, s(38) + lw, y + s(18), w - s(66) - lw, 1, Draw.PALE)
            else
                local icon = LOG_ICONS[line.k]
                if icon then
                    Draw.circle(bb, s(44), y + s(12), s(13), Draw.PAPER)
                    Draw.ring(bb, s(44), y + s(12), s(13), 1, Draw.MID)
                    Draw.icon(bb, icon, s(44), y + s(12), s(16))
                end
                for i, text in ipairs(row.wrapped) do
                    Draw.text(bb, text, face, s(70), y + (i - 1) * line_h + s(1), text_w, line_h, "left")
                end
            end
            y = y + row.h
        end
        page_footer(ctx, page, #pages, t, o.on_page)
    end }
end

-- Settings: language and about. opts: t, lang, languages ({ code, name }), version, on_lang(code), on_back.
function Pages.settings(o)
    return { draw = function(_, ctx)
        local bb, w, h, t = ctx.bb, ctx.w, ctx.h, o.t
        Draw.rect(bb, 0, 0, w, h, Draw.WHITE)
        local y = header(ctx, t.settings, nil, o.on_back) + s(24)
        Draw.text(bb, t.language:upper(), Draw.face("bold", s(13)), s(30), y, w, s(24), "left", Draw.DARK)
        y = y + s(32)
        for _, lang in ipairs(o.languages) do
            local on = lang[1] == o.lang
            Draw.pill(bb, s(30), y, w - s(60), s(50), on and Draw.INK or Draw.WHITE, on and nil or Draw.BLACK, s(1.5))
            Draw.text(bb, lang[2], Draw.face("bold", s(18)), s(30), y, w - s(60), s(50), "center", on and Draw.WHITE or Draw.BLACK)
            ctx:hit(s(30), y, w - s(60), s(50), function() o.on_lang(lang[1]) end)
            y = y + s(62)
        end
        y = y + s(16)
        Draw.text(bb, t.about:upper(), Draw.face("bold", s(13)), s(30), y, w, s(24), "left", Draw.DARK)
        y = y + s(32)
        local face = Draw.face("sans", s(15))
        y = y + Draw.paragraph(bb, t.about_text, face, s(30), y, w - s(60), s(22)) + s(12)
        y = y + Draw.paragraph(bb, string.format(t.version, o.version) .. " · Beater Studios", face, s(30), y, w - s(60), s(22), Draw.DARK) + s(12)
        y = y + Draw.paragraph(bb, t.license, face, s(30), y, w - s(60), s(22), Draw.DARK) + s(12)
        Draw.paragraph(bb, t.trademarks, Draw.face("sans", s(13)), s(30), y, w - s(60), s(19), Draw.MID)
    end }
end

return Pages
