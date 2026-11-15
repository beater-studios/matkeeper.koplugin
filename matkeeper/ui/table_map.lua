local Draw = require("matkeeper/ui/draw")
local Layouts = require("matkeeper/layouts")

-- The table in miniature, as one player sees it: every block where it sits, turned to that player's
-- view. It shows commander damage by seat, so a number needs no name next to it. A map is
-- { w, h, cells = { { x, y, w, h, player } } } in screen coordinates, as the table is laid out.
local TableMap = {}

local s = Draw.s

-- The map's width and height for a viewer at seat, as large as fits in max_w x max_h.
function TableMap.fit(map, seat, max_w, max_h)
    local w, h = Layouts.local_size(map.w, map.h, seat)
    local scale = math.max(0, math.min(max_w / w, max_h / h))
    return math.floor(w * scale), math.floor(h * scale)
end

-- The cells in the viewer's coordinates, inside x, y, w, h (a box from TableMap.fit).
function TableMap.cells(map, seat, x, y, w, h)
    local lw, lh = Layouts.local_size(map.w, map.h, seat)
    local sx, sy = w / lw, h / lh
    local cells = {}
    for _, cell in ipairs(map.cells) do
        local ax, ay = Layouts.to_local(seat, map.w, map.h, cell.x, cell.y)
        local bx, by = Layouts.to_local(seat, map.w, map.h, cell.x + cell.w - 1, cell.y + cell.h - 1)
        local x0, y0 = math.min(ax, bx), math.min(ay, by)
        local x1, y1 = math.max(ax, bx) + 1, math.max(ay, by) + 1
        cells[#cells + 1] = { x = x + x0 * sx, y = y + y0 * sy, w = (x1 - x0) * sx, h = (y1 - y0) * sy, player = cell.player }
    end
    return cells
end

-- A cell split in parts, one per commander of that player: side by side along its longer side, or in
-- stacked strips when stacked is true.
function TableMap.parts(cell, count, gap, stacked)
    if count <= 1 then
        return { { x = cell.x, y = cell.y, w = cell.w, h = cell.h, k = 1 } }
    end
    if stacked == nil then
        stacked = cell.h > cell.w
    end
    local parts = {}
    for k = 1, count do
        if not stacked then
            local pw = (cell.w - gap * (count - 1)) / count
            parts[k] = { x = cell.x + (k - 1) * (pw + gap), y = cell.y, w = pw, h = cell.h, k = k }
        else
            local ph = (cell.h - gap * (count - 1)) / count
            parts[k] = { x = cell.x, y = cell.y + (k - 1) * (ph + gap), w = cell.w, h = ph, k = k }
        end
    end
    return parts
end

-- The small map of a block. o: map, seat, match, i (the block's player), x, y, w, h. Each other player's
-- cell shows the commander damage they dealt to player i, empty at 0 and inverted at the lethal amount.
-- With partners, the cell shows the higher of the two, whole: split, the numbers would be too small to
-- read, and the large map shows both.
function TableMap.draw_small(bb, o)
    local match, i = o.match, o.i
    local limit = match:rules().commander_damage
    Draw.rect(bb, o.x, o.y, o.w, o.h, Draw.INK, s(6))
    local pad, gap = s(3), s(2)
    local cells = TableMap.cells(o.map, o.seat, o.x + pad, o.y + pad, o.w - 2 * pad, o.h - 2 * pad)
    for _, cell in ipairs(cells) do
        local inner = { x = cell.x + gap / 2, y = cell.y + gap / 2, w = cell.w - gap, h = cell.h - gap, player = cell.player }
        local other = match.players[cell.player]
        if cell.player == i then
            Draw.rect(bb, inner.x, inner.y, inner.w, inner.h, Draw.MID, s(3))
        else
            local value = 0
            for k = 1, other.commanders or 1 do
                value = math.max(value, match:commander_damage(i, cell.player, k))
            end
            local lethal = limit and value >= limit
            Draw.rect(bb, inner.x, inner.y, inner.w, inner.h, lethal and Draw.BLACK or (other.out and Draw.PALE or Draw.WHITE), s(3))
            if value > 0 then
                local px = math.max(6, math.min(inner.h * 0.78, inner.w * 0.5))
                Draw.text(bb, tostring(value), Draw.face("bold", px), inner.x, inner.y, inner.w, inner.h, "center", lethal and Draw.WHITE or Draw.BLACK)
            end
        end
    end
end

-- The large map of the commander damage dialog. o: map, seat, match, i, x, y, w, h, on_change(source, k,
-- delta). Each part shows the other player's name and the damage, with the left half taking and the
-- right half giving, as on a block (a hold moves 5).
function TableMap.draw_large(ctx, o)
    local bb, match, i = ctx.bb, o.match, o.i
    local limit = match:rules().commander_damage
    Draw.rect(bb, o.x, o.y, o.w, o.h, Draw.INK, s(14))
    local pad, gap = s(8), s(8)
    local cells = TableMap.cells(o.map, o.seat, o.x + pad, o.y + pad, o.w - 2 * pad, o.h - 2 * pad)
    for _, cell in ipairs(cells) do
        local inner = { x = cell.x + gap / 2, y = cell.y + gap / 2, w = cell.w - gap, h = cell.h - gap }
        local other = match.players[cell.player]
        if cell.player == i then
            Draw.rect(bb, inner.x, inner.y, inner.w, inner.h, Draw.DARK, s(8))
            Draw.icon(bb, "heart", inner.x + inner.w / 2, inner.y + inner.h / 2, math.min(inner.w, inner.h) * 0.3, Draw.LIGHT)
        else
            local count = other.commanders or 1
            -- Strips keep a name readable; only a narrow, tall cell splits side by side.
            for _, part in ipairs(TableMap.parts(inner, count, s(4), inner.w > inner.h * 0.7)) do
                local value = match:commander_damage(i, cell.player, part.k)
                local lethal = limit and value >= limit
                local ink = lethal and Draw.WHITE or (other.out and Draw.MID or Draw.BLACK)
                Draw.rect(bb, part.x, part.y, part.w, part.h, lethal and Draw.BLACK or Draw.WHITE, s(8))
                local label = count > 1 and string.format("%s (%d)", other.name, part.k) or other.name
                local name_h = math.min(s(24), part.h * 0.28)
                Draw.text(bb, label, Draw.face("bold", math.max(s(11), name_h * 0.62)), part.x + s(6), part.y + s(4), part.w - s(12), name_h, "center", lethal and Draw.LIGHT or Draw.DARK)
                local number_h = part.h - name_h - s(8)
                local px = math.min(number_h * 0.8, part.w * 0.34)
                Draw.text(bb, tostring(value), Draw.face("serif", px), part.x, part.y + name_h + s(4), part.w, number_h, "center", ink)
                local arm = math.max(s(6), math.min(part.w, part.h) * 0.07)
                local my = part.y + name_h + s(4) + number_h / 2
                local sign = lethal and Draw.MID or Draw.LIGHT
                Draw.sign(bb, part.x + part.w * 0.12, my, arm, s(2.5), false, sign)
                Draw.sign(bb, part.x + part.w * 0.88, my, arm, s(2.5), true, sign)
                local source, k = cell.player, part.k
                ctx:hit(part.x, part.y, part.w / 2, part.h, function() o.on_change(source, k, -1) end, function() o.on_change(source, k, -5) end)
                ctx:hit(part.x + part.w / 2, part.y, part.w / 2, part.h, function() o.on_change(source, k, 1) end, function() o.on_change(source, k, 5) end)
            end
        end
    end
end

return TableMap
