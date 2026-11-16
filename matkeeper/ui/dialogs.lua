local Draw = require("matkeeper/ui/draw")
local Layouts = require("matkeeper/layouts")
local TableMap = require("matkeeper/ui/table_map")

-- Modal views drawn over the darkened table, facing a seat. Each returns a view for Surface:show_modal.
local Dialogs = {}

local s = Draw.s

-- The box: a drop shadow, a white panel with a thin inner line. Returns its corner.
function Dialogs.frame(ctx, bw, bh)
    local bb = ctx.bb
    local x0 = math.floor((ctx.w - bw) / 2)
    local y0 = math.floor((ctx.h - bh) / 2)
    Draw.rect(bb, x0 + s(6), y0 + s(8), bw, bh, Draw.BLACK, s(18))
    Draw.rect(bb, x0, y0, bw, bh, Draw.WHITE, s(18))
    Draw.border(bb, x0, y0, bw, bh, s(3), Draw.BLACK, s(18))
    Draw.border(bb, x0 + s(7), y0 + s(7), bw - s(14), bh - s(14), 1, Draw.MID, s(13))
    -- The panel swallows taps, so only taps outside it count as "outside".
    ctx:hit(x0, y0, bw, bh, nil)
    return x0, y0
end

local function width_for(ctx)
    return math.min(ctx.w - 2 * s(30), s(540))
end

local function title(ctx, x0, y, bw, text, subtitle)
    Draw.text(ctx.bb, text, Draw.face("serif", s(26)), x0 + s(20), y, bw - s(40), s(40), "center")
    y = y + s(40)
    if subtitle then
        Draw.text(ctx.bb, subtitle, Draw.face("sans", s(16)), x0 + s(20), y, bw - s(40), s(24), "center", Draw.DARK)
        y = y + s(28)
    end
    return y
end

-- The rotate button stays at the same corner of the screen (top right) whatever the seat, outside
-- the box, so it can be tapped again without moving. Dialogs that have it keep that corner clear.
local function rotate_button(ctx, on_rotate)
    if not on_rotate then
        return
    end
    local pane = ctx.pane
    local cx, cy = Layouts.to_local(pane.seat or "bottom", pane.w, pane.h, pane.w - s(40), s(40))
    Draw.circle(ctx.bb, cx, cy, s(26), Draw.BLACK)
    Draw.round_button(ctx.bb, cx, cy, s(22), "rotate", Draw.PAPER, Draw.BLACK, Draw.BLACK)
    ctx:hit(cx - s(32), cy - s(32), s(64), s(64), on_rotate)
end

-- Room above and below a dialog. When the rotate corner falls on the top or bottom of the box, the
-- box leaves it free.
local function margin_y(ctx, rotating)
    if rotating and ctx.h > ctx.w then
        return s(76)
    end
    return s(24)
end

local function stepper_button(ctx, cx, cy, plus, on_tap, on_hold)
    local r = s(19)
    Draw.circle(ctx.bb, cx, cy, r, Draw.WHITE)
    Draw.ring(ctx.bb, cx, cy, r, s(2), Draw.BLACK)
    Draw.hline(ctx.bb, cx - s(8), cy - s(1.5), s(16), s(3), Draw.BLACK)
    if plus then
        ctx.bb:paintRect(math.floor(cx - s(1.5)), math.floor(cy - s(8)), math.max(2, s(3)), s(16), Draw.BLACK)
    end
    ctx:hit(cx - r - s(6), cy - r - s(6), 2 * r + s(12), 2 * r + s(12), on_tap, on_hold)
end

local ROW_H = 52

local function row_height(row)
    if row.kind == "map" then
        return row.height or s(160)
    elseif row.kind == "separator" then
        return s(16)
    elseif row.kind == "text" then
        return s(30)
    end
    return s(ROW_H) + s(10)
end

local TAB_H = 44

-- Tabs under the title: { label, selected, on_tap }. Returns the y below them.
function Dialogs.tabs(ctx, tabs, lx, y, lw)
    local bb = ctx.bb
    if not tabs then
        return y
    end
    local th = s(TAB_H)
    Draw.rect(bb, lx, y, lw, th, Draw.PAPER, th / 2)
    local tw = lw / #tabs
    for n, tab in ipairs(tabs) do
        local tx = lx + (n - 1) * tw
        if tab.selected then
            Draw.pill(bb, tx + s(3), y + s(3), tw - s(6), th - s(6), Draw.INK)
        end
        Draw.text(bb, tab.label, Draw.face("bold", s(16)), tx + s(10), y, tw - s(20), th, "center", tab.selected and Draw.WHITE or Draw.BLACK)
        if not tab.selected then
            ctx:hit(tx, y - s(4), tw, th + s(8), tab.on_tap)
        end
    end
    y = y + th + s(14)
    return y
end

-- Draws rows from y, in lx..lx+lw. Returns the y below them.
function Dialogs.rows(ctx, rows, lx, y, lw)
    local bb = ctx.bb
    for _, row in ipairs(rows) do
        local rh = row_height(row)
        if row.kind == "map" then
            TableMap.draw_large(ctx, { map = row.map, seat = row.seat, match = row.match, i = row.i,
                x = lx + (lw - row.map_w) / 2, y = y, w = row.map_w, h = row.map_h, on_change = row.on_change })
        elseif row.kind == "separator" then
            Draw.hline(bb, lx + s(10), y + rh / 2, lw - s(20), s(1.5), Draw.PALE)
        elseif row.kind == "text" then
            Draw.text(bb, row.label, Draw.face("sans", s(15)), lx, y, lw, rh, "center", Draw.DARK)
        elseif row.kind == "stepper" then
            local h = s(ROW_H)
            Draw.rect(bb, lx, y, lw, h, Draw.PAPER, h / 2)
            -- The label ends before the minus button, which starts 173 from the right edge.
            Draw.text(bb, row.label, Draw.face("bold", s(16)), lx + s(20), y, lw - s(205), h, "left")
            local cx = lx + lw - s(30)
            stepper_button(ctx, cx, y + h / 2, true, row.on_plus, row.on_plus_hold)
            Draw.text(bb, tostring(row.value), Draw.face("serif", s(22)), cx - s(96), y, s(56), h, "center")
            stepper_button(ctx, cx - s(124), y + h / 2, false, row.on_minus, row.on_minus_hold)
        elseif row.kind == "toggle" then
            local h = s(ROW_H)
            Draw.pill(bb, lx, y, lw, h, Draw.WHITE, Draw.BLACK, s(1.5))
            Draw.text(bb, row.label, Draw.face("bold", s(16)), lx + s(20), y, lw - s(110), h, "left")
            local tw, th = s(56), s(30)
            local tx, ty = lx + lw - s(20) - tw, y + (h - th) / 2
            Draw.pill(bb, tx, ty, tw, th, row.on and Draw.INK or Draw.PALE)
            Draw.circle(bb, row.on and (tx + tw - th / 2) or (tx + th / 2), ty + th / 2, th / 2 - s(4), Draw.WHITE)
            ctx:hit(lx, y, lw, h, row.on_tap)
        else
            local h = s(ROW_H)
            local filled = row.selected or row.danger
            local ink = filled and Draw.WHITE or (row.disabled and Draw.LIGHT or Draw.BLACK)
            Draw.pill(bb, lx, y, lw, h, filled and Draw.INK or Draw.WHITE, (not filled) and (row.disabled and Draw.PALE or Draw.BLACK) or nil, s(1.5))
            local tx = lx + s(24)
            if row.radio then
                Draw.circle(bb, lx + s(30), y + h / 2, s(10), Draw.WHITE)
                if not filled then
                    Draw.ring(bb, lx + s(30), y + h / 2, s(10), s(2), Draw.BLACK)
                else
                    Draw.circle(bb, lx + s(30), y + h / 2, s(5), Draw.INK)
                end
                tx = lx + s(54)
            elseif row.icon then
                Draw.icon(bb, row.icon, lx + s(34), y + h / 2, s(24), ink)
                tx = lx + s(58)
            end
            local align = (row.radio or row.icon or row.value) and "left" or "center"
            local label_w = lw - (tx - lx) - s(20) - (row.value and s(110) or 0)
            if align == "center" then
                Draw.text(bb, row.label, Draw.face("bold", s(18)), lx, y, lw, h, "center", ink)
            else
                Draw.text(bb, row.label, Draw.face("bold", s(18)), tx, y, label_w, h, "left", ink)
            end
            if row.value then
                Draw.text(bb, row.value, Draw.face(row.value_face or "serif", s(row.value_px or 20)), lx + lw - s(130), y, s(110), h, "right", filled and Draw.LIGHT or Draw.MID)
            end
            if row.on_tap and not row.disabled then
                ctx:hit(lx, y, lw, h, row.on_tap)
            end
        end
        y = y + rh
    end
    return y
end

-- The buttons at the bottom of a box at x0, y0 of bw x bh: { text, style, on_tap }.
function Dialogs.buttons(ctx, buttons, x0, y0, bw, bh)
    local bb = ctx.bb
    if buttons and #buttons > 0 then
        local n = #buttons
        local gap = s(20)
        local bwid = (bw - s(60) - gap * (n - 1)) / n
        local by = y0 + bh - s(70)
        for b, button in ipairs(buttons) do
            local bx = x0 + s(30) + (b - 1) * (bwid + gap)
            Draw.button(bb, bx, by, bwid, s(46), button.text, button.style, s(16))
            if button.style ~= "disabled" then
                ctx:hit(bx, by - s(4), bwid, s(54), button.on_tap)
            end
        end
    end
end

-- A list dialog. spec: title, subtitle, rows, buttons, on_rotate, page (current page, 1-based),
-- on_page(page). Rows:
--   { label, value, icon, on_tap, selected, radio, danger, disabled }
--   { kind = "stepper", label, value, on_minus, on_plus, on_minus_hold, on_plus_hold }
--   { kind = "toggle", label, on, on_tap }
--   { kind = "separator" } and { kind = "text", label }
--   { kind = "map", map, seat, match, i, on_change(source, k, delta) }: the commander damage of player i
--     on the table map (TableMap.draw_large), as large as the other rows leave room for
-- Buttons: { text, style ("filled", "outline", "disabled"), on_tap }. Tabs, under the title:
-- { label, selected, on_tap }.
function Dialogs.list(spec)
    return { draw = function(_, ctx)
        local bb = ctx.bb
        local head = s(40) + (spec.subtitle and s(28) or 0) + s(24) + (spec.tabs and s(TAB_H + 14) or 0)
        local foot = (spec.buttons and #spec.buttons > 0) and s(76) or s(16)
        local room = ctx.h - 2 * margin_y(ctx, spec.on_rotate) - head - foot - s(16)
        -- Lying down (a player at a side of the table), a dialog with columns uses two of them, but only
        -- when its rows do not fit in one.
        local rows_height = 0
        for _, row in ipairs(spec.rows) do
            rows_height = rows_height + (row.kind == "map" and 0 or row_height(row))
        end
        local columns = (spec.columns and ctx.w > ctx.h and rows_height > room) and 2 or 1
        local bw = columns > 1 and math.min(ctx.w - 2 * s(30), s(780)) or width_for(ctx)
        local lx, lw = 0, bw - s(56)
        local gap = s(20)
        local col_w = (lw - gap * (columns - 1)) / columns
        -- A map takes the height the other rows leave, keeping the table's shape.
        local others = 0
        for _, row in ipairs(spec.rows) do
            if row.kind ~= "map" then
                others = others + row_height(row)
            end
        end
        local total = others
        for _, row in ipairs(spec.rows) do
            if row.kind == "map" then
                local mw, mh = TableMap.fit(row.map, row.seat, col_w, math.max(s(150), room - others - s(10)))
                row.map_w, row.map_h, row.height = mw, mh, mh + s(10)
                total = total + row.height
            end
        end
        -- Columns of rows that fit the height, keeping room for the page footer when they do not all fit.
        -- When everything fits, the columns share the rows evenly instead of filling the first one.
        local fits = total <= room * columns
        local limit = fits and room or room - s(48)
        local function height_of(chunk)
            local hsum = 0
            for _, row in ipairs(chunk or {}) do
                hsum = hsum + row_height(row)
            end
            return hsum
        end
        local chunks
        if fits and columns > 1 then
            local first, second = {}, {}
            local half = math.ceil(#spec.rows / 2)
            for n, row in ipairs(spec.rows) do
                local chunk = n <= half and first or second
                chunk[#chunk + 1] = row
            end
            if height_of(first) <= room and height_of(second) <= room then
                chunks = { first, second }
            end
        end
        if not chunks then
            local used = 0
            chunks = { {} }
            for _, row in ipairs(spec.rows) do
                local rh = row_height(row)
                if used + rh > limit and #chunks[#chunks] > 0 then
                    chunks[#chunks + 1] = {}
                    used = 0
                end
                local chunk = chunks[#chunks]
                chunk[#chunk + 1] = row
                used = used + rh
            end
        end
        local pages = math.ceil(#chunks / columns)
        local page = math.max(1, math.min(spec.page or 1, pages))
        -- Every page as tall as the tallest column, so the box does not jump between pages.
        local content = 0
        for _, chunk in ipairs(chunks) do
            content = math.max(content, height_of(chunk))
        end
        if pages > 1 then
            content = content + s(48)
        end
        local bh = head + content + foot + s(8)
        local x0, y0 = Dialogs.frame(ctx, bw, bh)
        local y = title(ctx, x0, y0 + s(16), bw, spec.title, spec.subtitle) + s(6)
        rotate_button(ctx, spec.on_rotate)
        lx = x0 + s(28)
        y = Dialogs.tabs(ctx, spec.tabs, lx, y, lw)
        for c = 1, columns do
            local chunk = chunks[(page - 1) * columns + c]
            if chunk then
                Dialogs.rows(ctx, chunk, lx + (c - 1) * (col_w + gap), y, col_w)
            end
        end
        if pages > 1 then
            local py = y0 + head + content - s(40)
            Draw.text(bb, string.format("%d / %d", page, pages), Draw.face("sans", s(15)), lx, py, lw, s(36), "center", Draw.DARK)
            Draw.icon(bb, "chevron_left", lx + s(30), py + s(18), s(24), page > 1 and Draw.BLACK or Draw.PALE)
            Draw.icon(bb, "chevron_right", lx + lw - s(30), py + s(18), s(24), page < pages and Draw.BLACK or Draw.PALE)
            ctx:hit(lx, py - s(6), s(90), s(48), function()
                if page > 1 then
                    spec.on_page(page - 1)
                end
            end)
            ctx:hit(lx + lw - s(90), py - s(6), s(90), s(48), function()
                if page < pages then
                    spec.on_page(page + 1)
                end
            end)
        end
        Dialogs.buttons(ctx, spec.buttons, x0, y0, bw, bh)
    end }
end

-- The life keypad. state: { digits = "" }. opts: t, name, on_digit(d), on_back(), on_apply(mode), on_rotate.
function Dialogs.keypad(o)
    return { draw = function(_, ctx)
        local bb, t = ctx.bb, o.t
        local bw = math.min(width_for(ctx), s(420))
        local key_h = s(54)
        local bh = s(40) + s(24) + s(70) + 4 * (key_h + s(10)) + s(80) + s(24)
        if bh > ctx.h - s(20) then
            key_h = math.floor((ctx.h - s(20) - s(40) - s(24) - s(70) - s(80) - s(24)) / 4 - s(10))
            bh = s(40) + s(24) + s(70) + 4 * (key_h + s(10)) + s(80) + s(24)
        end
        local x0, y0 = Dialogs.frame(ctx, bw, bh)
        rotate_button(ctx, o.on_rotate)
        local y = title(ctx, x0, y0 + s(16), bw, string.format(t.life_title, o.name)) + s(4)
        Draw.rect(bb, x0 + s(30), y, bw - s(60), s(58), Draw.PAPER, s(12))
        local shown = o.state.digits ~= "" and o.state.digits or "0"
        Draw.text(bb, shown, Draw.face("serif", s(40)), x0 + s(30), y, bw - s(60), s(58), "center", o.state.digits ~= "" and Draw.BLACK or Draw.LIGHT)
        y = y + s(70)
        local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "back", "0", "clear" }
        local kw = (bw - s(60) - 2 * s(12)) / 3
        for k, key in ipairs(keys) do
            local col, row = (k - 1) % 3, math.floor((k - 1) / 3)
            local kx = x0 + s(30) + col * (kw + s(12))
            local ky = y + row * (key_h + s(10))
            Draw.rect(bb, kx, ky, kw, key_h, Draw.WHITE, s(12))
            Draw.border(bb, kx, ky, kw, key_h, s(1.5), Draw.BLACK, s(12))
            if key == "back" then
                Draw.icon(bb, "chevron_left", kx + kw / 2, ky + key_h / 2, s(24))
                ctx:hit(kx, ky, kw, key_h, o.on_back)
            elseif key == "clear" then
                Draw.text(bb, "C", Draw.face("bold", s(22)), kx, ky, kw, key_h, "center")
                ctx:hit(kx, ky, kw, key_h, o.on_clear)
            else
                Draw.text(bb, key, Draw.face("serif", s(26)), kx, ky, kw, key_h, "center")
                ctx:hit(kx, ky, kw, key_h, function() o.on_digit(key) end)
            end
        end
        local by = y0 + bh - s(70)
        local labels = { { "subtract", t.subtract }, { "add", t.add }, { "set", t.set_value } }
        local bwid = (bw - s(60) - 2 * s(12)) / 3
        for b, entry in ipairs(labels) do
            local bx = x0 + s(30) + (b - 1) * (bwid + s(12))
            local enabled = o.state.digits ~= ""
            Draw.button(bb, bx, by, bwid, s(46), entry[2], enabled and (entry[1] == "set" and "filled" or "outline") or "disabled", s(15))
            if enabled then
                ctx:hit(bx, by - s(4), bwid, s(54), function() o.on_apply(entry[1]) end)
            end
        end
    end }
end

local function coin_row(ctx, results, cx, y, max_w)
    local n = #results
    local shown = math.min(n, 12)
    local per_row = math.min(shown, 6)
    local rows = math.ceil(shown / per_row)
    local size = math.min(s(84), (max_w - (per_row - 1) * s(12)) / per_row)
    local face = Draw.face("bold", math.max(s(11), size * 0.18))
    for idx = 1, shown do
        local col = (idx - 1) % per_row
        local row = math.floor((idx - 1) / per_row)
        local in_row = math.min(per_row, shown - row * per_row)
        local total = in_row * size + (in_row - 1) * s(12)
        local x = cx - total / 2 + col * (size + s(12)) + size / 2
        local yy = y + row * (size + s(30)) + size / 2
        Draw.picture(ctx.bb, "art/coin_" .. results[idx] .. ".png", x, yy, size, size)
        Draw.text(ctx.bb, ctx.text_side(results[idx]), face, x - size, yy + size / 2 + s(2), 2 * size, s(22), "center")
    end
    return rows * (size + s(30))
end

-- Coins: a number of coins or "until tails". state: { mode = "count"|"until", count, results, heads }.
-- opts: t, text, on_mode(mode), on_count(delta), on_flip(), on_close(), on_rotate.
function Dialogs.coins(o)
    return { draw = function(_, ctx)
        local bb, t, st = ctx.bb, o.t, o.state
        ctx.text_side = function(r)
            return r == "heads" and t.heads or t.tails
        end
        local bw = width_for(ctx)
        local bh = math.min(ctx.h - s(30), s(500))
        local x0, y0 = Dialogs.frame(ctx, bw, bh)
        local y = title(ctx, x0, y0 + s(16), bw, t.coins) + s(6)
        rotate_button(ctx, o.on_rotate)
        local sx, sw = x0 + s(40), bw - s(80)
        Draw.pill(bb, sx, y, sw, s(40), Draw.PAPER, Draw.BLACK, s(1.5))
        local half = sw / 2
        local count_mode = st.mode ~= "until"
        Draw.pill(bb, count_mode and sx + s(2) or sx + half, y + s(2), half - s(2), s(36), Draw.INK)
        Draw.text(bb, t.quantity, Draw.face("bold", s(15)), sx, y, half, s(40), "center", count_mode and Draw.WHITE or Draw.BLACK)
        Draw.text(bb, t.until_tails, Draw.face("bold", s(15)), sx + half, y, half, s(40), "center", count_mode and Draw.BLACK or Draw.WHITE)
        ctx:hit(sx, y, half, s(40), function() o.on_mode("count") end)
        ctx:hit(sx + half, y, half, s(40), function() o.on_mode("until") end)
        y = y + s(56)
        if count_mode then
            local cx = x0 + bw / 2
            stepper_button(ctx, cx - s(80), y + s(22), false, function() o.on_count(-1) end)
            Draw.text(bb, tostring(st.count), Draw.face("serif", s(36)), cx - s(40), y, s(80), s(44), "center")
            stepper_button(ctx, cx + s(80), y + s(22), true, function() o.on_count(1) end)
            y = y + s(56)
        end
        if st.results then
            local used = coin_row(ctx, st.results, x0 + bw / 2, y, bw - s(60))
            y = y + used
            Draw.hline(bb, x0 + s(50), y, bw - s(100), s(1.5), Draw.PALE)
            Draw.text(bb, o.text:heads_count(st.heads), Draw.face("serif", s(28)), x0, y + s(6), bw, s(40), "center")
        end
        local by = y0 + bh - s(70)
        local bwid = (bw - s(80)) / 2
        Draw.button(bb, x0 + s(30), by, bwid, s(46), st.results and t.flip_again or t.flip, "outline", s(16))
        ctx:hit(x0 + s(30), by - s(4), bwid, s(54), o.on_flip)
        Draw.button(bb, x0 + s(50) + bwid, by, bwid, s(46), t.close, "filled", s(16))
        ctx:hit(x0 + s(50) + bwid, by - s(4), bwid, s(54), o.on_close)
    end }
end

-- Dice. state: { count, faces, results, sum }. opts: t, on_count(delta), on_faces(f), on_roll(), on_close(), on_rotate.
Dialogs.FACES = { 4, 6, 8, 10, 12, 20 }

function Dialogs.dice(o)
    return { draw = function(_, ctx)
        local bb, t, st = ctx.bb, o.t, o.state
        local bw = width_for(ctx)
        local bh = math.min(ctx.h - s(30), s(520))
        local x0, y0 = Dialogs.frame(ctx, bw, bh)
        local y = title(ctx, x0, y0 + s(16), bw, t.dice) + s(4)
        rotate_button(ctx, o.on_rotate)
        local n = #Dialogs.FACES
        local fw = (bw - s(60) - (n - 1) * s(8)) / n
        for f, faces in ipairs(Dialogs.FACES) do
            local fx = x0 + s(30) + (f - 1) * (fw + s(8))
            local on = st.faces == faces
            Draw.pill(bb, fx, y, fw, s(40), on and Draw.INK or Draw.WHITE, on and nil or Draw.BLACK, s(1.5))
            Draw.text(bb, "d" .. faces, Draw.face("bold", s(16)), fx, y, fw, s(40), "center", on and Draw.WHITE or Draw.BLACK)
            ctx:hit(fx, y - s(4), fw, s(48), function() o.on_faces(faces) end)
        end
        y = y + s(56)
        local cx = x0 + bw / 2
        stepper_button(ctx, cx - s(80), y + s(22), false, function() o.on_count(-1) end)
        Draw.text(bb, tostring(st.count), Draw.face("serif", s(36)), cx - s(40), y, s(80), s(44), "center")
        stepper_button(ctx, cx + s(80), y + s(22), true, function() o.on_count(1) end)
        y = y + s(60)
        if st.results then
            local count = #st.results
            local per_row = math.min(count, 5)
            local size = count == 1 and s(130) or math.min(s(80), (bw - s(60) - (per_row - 1) * s(12)) / per_row)
            local art = st.faces == 20 and "art/d20.png" or "art/d6.png"
            for idx, value in ipairs(st.results) do
                local col = (idx - 1) % per_row
                local row = math.floor((idx - 1) / per_row)
                local in_row = math.min(per_row, count - row * per_row)
                local total = in_row * size + (in_row - 1) * s(12)
                local dx = cx - total / 2 + col * (size + s(12)) + size / 2
                local dy = y + row * (size + s(10)) + size / 2
                Draw.picture(bb, art, dx, dy, size, size)
                local offset = st.faces == 20 and size * 0.08 or 0
                Draw.text(bb, tostring(value), Draw.face("serif", size * (st.faces == 20 and 0.17 or 0.42)), dx - size / 2, dy - size / 2 + offset, size, size, "center")
            end
            local rows = math.ceil(count / per_row)
            y = y + rows * (size + s(10))
            if count > 1 then
                Draw.text(bb, string.format(t.sum, st.sum), Draw.face("serif", s(26)), x0, y, bw, s(36), "center")
            end
        end
        local by = y0 + bh - s(70)
        local bwid = (bw - s(80)) / 2
        Draw.button(bb, x0 + s(30), by, bwid, s(46), st.results and t.roll_again or t.roll, "outline", s(16))
        ctx:hit(x0 + s(30), by - s(4), bwid, s(54), o.on_roll)
        Draw.button(bb, x0 + s(50) + bwid, by, bwid, s(46), t.close, "filled", s(16))
        ctx:hit(x0 + s(50) + bwid, by - s(4), bwid, s(54), o.on_close)
    end }
end

-- Pokémon Checkup. opts: match, t, steps, on_flip(key), on_back(), on_pass().
function Dialogs.checkup(o)
    return { draw = function(_, ctx)
        local bb, t, match = ctx.bb, o.t, o.match
        local bw = width_for(ctx)
        local bh = ctx.h - s(60)
        local x0, y0 = Dialogs.frame(ctx, bw, bh)
        local y = title(ctx, x0, y0 + s(16), bw, t.checkup_title, t.checkup_sub) + s(6)
        local lx, lw = x0 + s(26), bw - s(52)
        local icons = { poison = "drop", burn = "flame", sleep = "sleep", paralysis = "bolt" }
        local order = { match.current, match:other(match.current) }
        local by = y0 + bh - s(70)
        -- Row sizes: the usual ones, or tighter ones when both Active Pokémon have many conditions.
        local function sizes(compact)
            if compact then
                return { row = s(50), gap = s(6), head = s(22), after = s(4) }
            end
            return { row = s(58), gap = s(10), head = s(26), after = s(8) }
        end
        local function needed(z)
            local total = 0
            for _, who in ipairs(order) do
                total = total + z.head + z.after
                local any = false
                for _, step in ipairs(o.steps) do
                    if step.p == who then
                        any = true
                        local extra = step.coin or step.c == "paralysis"
                        total = total + z.row + (extra and s(34) or 0) + z.gap
                    end
                end
                if not any then
                    total = total + s(36)
                end
            end
            return total
        end
        local z = sizes(false)
        if y + needed(z) > by - s(40) then
            z = sizes(true)
        end
        for _, who in ipairs(order) do
            local p = match.players[who]
            Draw.text(bb, string.format(t.active_of, p.name:upper()), Draw.face("bold", s(13)), lx, y, lw, s(22), "left", Draw.DARK)
            y = y + z.head
            local any = false
            for _, step in ipairs(o.steps) do
                if step.p == who then
                    any = true
                    local extra = step.coin or step.c == "paralysis"
                    local R = z.row
                    local hgt = extra and (R + s(34)) or R
                    Draw.rect(bb, lx, y, lw, hgt, Draw.PAPER, s(12))
                    Draw.border(bb, lx, y, lw, hgt, s(1.2), Draw.BLACK, s(12))
                    Draw.circle(bb, lx + s(32), y + R / 2, s(18), Draw.INK)
                    Draw.icon(bb, icons[step.c], lx + s(32), y + R / 2, s(20), Draw.WHITE)
                    Draw.text(bb, t.conditions[step.c], Draw.face("bold", s(18)), lx + s(62), y + (R - s(38)) / 2, lw * 0.5, s(38), "left")
                    if step.damage then
                        local label = string.format(t.damage, step.damage)
                        local face = Draw.face("bold", s(15))
                        local pw = Draw.text_width(label, face) + s(28)
                        Draw.pill(bb, lx + lw - s(16) - pw, y + (R - s(30)) / 2, pw, s(30), Draw.WHITE, Draw.BLACK, s(1.5))
                        Draw.text(bb, label, face, lx + lw - s(16) - pw, y + (R - s(30)) / 2, pw, s(30), "center")
                    end
                    local ly = y + R - s(6)
                    if step.coin then
                        if step.result then
                            Draw.picture(bb, "art/coin_" .. step.result .. ".png", lx + s(74), ly + s(16), s(28), s(28))
                            local key = step.c .. "_" .. step.result
                            Draw.text(bb, t[key], Draw.face("sans", s(16)), lx + s(96), ly, lw - s(110), s(32), "left", Draw.DARK)
                        else
                            local label = t.flip_coin
                            local face = Draw.face("bold", s(15))
                            local pw = Draw.text_width(label, face) + s(56)
                            Draw.pill(bb, lx + s(60), ly, pw, s(32), Draw.INK)
                            Draw.icon(bb, "coin", lx + s(80), ly + s(16), s(22), Draw.WHITE)
                            Draw.text(bb, label, face, lx + s(96), ly, pw - s(40), s(32), "left", Draw.WHITE)
                            ctx:hit(lx + s(56), ly - s(6), pw + s(8), s(44), function() o.on_flip(step.key) end)
                            Draw.text(bb, step.c == "sleep" and t.heads_wakes or t.heads_recovers, Draw.face("sans", s(14)), lx + s(72) + pw, ly, lw - pw - s(80), s(32), "left", Draw.MID)
                        end
                    elseif step.c == "paralysis" then
                        local text = step.recovers and t.paralysis_recovers or string.format(t.paralysis_stays, p.name)
                        Draw.text(bb, text, Draw.face("sans", s(15)), lx + s(62), ly, lw - s(76), s(32), "left", Draw.DARK)
                    end
                    y = y + hgt + z.gap
                end
            end
            if not any then
                local text = p.conditions.confusion and t.confused_nothing or t.nothing
                Draw.text(bb, text, Draw.face("sans", s(16)), lx, y, lw, s(28), "left", Draw.DARK)
                y = y + s(36)
            end
            y = y + z.after
        end
        local ready = match:checkup_ready(o.steps)
        if not ready then
            Draw.text(bb, t.pending_coins, Draw.face("italic", s(15)), x0, by - s(36), bw, s(28), "center", Draw.DARK)
        end
        local bwid = (bw - s(80)) / 2
        Draw.button(bb, x0 + s(30), by, bwid, s(46), t.back_to_turn, "outline", s(16))
        ctx:hit(x0 + s(30), by - s(4), bwid, s(54), o.on_back)
        Draw.button(bb, x0 + s(50) + bwid, by, bwid, s(46), t.pass_turn, ready and "filled" or "disabled", s(16))
        if ready then
            ctx:hit(x0 + s(50) + bwid, by - s(4), bwid, s(54), o.on_pass)
        end
    end }
end

-- Pokémon: who calls the coin, heads or tails, the flip and who starts.
-- state: { caller, side, result, winner }. opts: match, t, on_caller(i), on_side(side), on_start(i), on_skip().
function Dialogs.coin_call(o)
    local rows = {}
    local t, st, match = o.t, o.state, o.match
    if not st.caller then
        for i, p in ipairs(match.players) do
            rows[#rows + 1] = { label = p.name, on_tap = function() o.on_caller(i) end }
        end
        return Dialogs.list{ title = t.who_starts, subtitle = t.caller, rows = rows, buttons = { { text = t.close, style = "outline", on_tap = o.on_skip } } }
    elseif not st.result then
        rows[1] = { label = t.heads, icon = "star", on_tap = function() o.on_side("heads") end }
        rows[2] = { label = t.tails, icon = "crown", on_tap = function() o.on_side("tails") end }
        return Dialogs.list{ title = t.who_starts, subtitle = string.format(t.calls, match.players[st.caller].name), rows = rows, buttons = { { text = t.close, style = "outline", on_tap = o.on_skip } } }
    end
    local side = st.result == "heads" and t.heads_lower or t.tails_lower
    rows[1] = { kind = "text", label = string.format(t.won_flip, side, match.players[st.winner].name) }
    for i, p in ipairs(match.players) do
        rows[#rows + 1] = { label = string.format(t.starts, p.name), selected = i == st.winner, on_tap = function() o.on_start(i) end }
    end
    return Dialogs.list{ title = t.who_starts, rows = rows }
end

return Dialogs
