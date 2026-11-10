-- Table layouts: the screen split in bands (rows or columns), each band with one or two cells.
-- A cell is "p" (a player) or "e" (empty, where the controls go). Layouts come from a rule, not a
-- fixed list: every combination is generated and the ones with cells too small are dropped.
local Layouts = {}

Layouts.MIN_PLAYERS = 2
Layouts.MAX_PLAYERS = 6
local MAX_BANDS = 4
-- The smallest side a cell may have, as a share of the screen's smallest side.
local MIN_SIDE = 0.3
-- The 2-player face to face layout keeps a bar of controls between the two halves.
Layouts.BAR = "r:p.p"

local SEAT_DEGREES = { bottom = 0, left = 90, top = 180, right = 270 }
local SEAT_ORDER = { "bottom", "left", "top", "right" }
Layouts.SEATS = SEAT_ORDER

function Layouts.encode(layout)
    local bands = {}
    for i, band in ipairs(layout.bands) do
        bands[i] = table.concat(band)
    end
    return (layout.columns and "c:" or "r:") .. table.concat(bands, ".")
end

function Layouts.decode(id)
    if type(id) ~= "string" then
        return nil
    end
    local kind, rest = id:match("^([rc]):([pe%.]+)$")
    if not kind then
        return nil
    end
    local bands = {}
    for band in rest:gmatch("[pe]+") do
        local cells = {}
        for cell in band:gmatch("[pe]") do
            cells[#cells + 1] = cell
        end
        if #cells < 1 or #cells > 2 then
            return nil
        end
        bands[#bands + 1] = cells
    end
    if #bands < 1 or #bands > MAX_BANDS then
        return nil
    end
    return { columns = kind == "c", bands = bands, id = id }
end

function Layouts.players(layout)
    local n = 0
    for _, band in ipairs(layout.bands) do
        for _, cell in ipairs(band) do
            if cell == "p" then
                n = n + 1
            end
        end
    end
    return n
end

function Layouts.has_empty(layout)
    for _, band in ipairs(layout.bands) do
        for _, cell in ipairs(band) do
            if cell == "e" then
                return true
            end
        end
    end
    return false
end

-- Cells as rectangles inside (x, y, w, h). The face to face layout leaves room for the bar.
function Layouts.rects(layout, x, y, w, h, gap, bar)
    local cells = {}
    local bands = layout.bands
    local n = #bands
    local reserved = (bar and layout.id == Layouts.BAR) and (bar + gap) or 0
    local across = layout.columns and w or (h - reserved)
    local band_size = (across - gap * (n - 1)) / n
    local offset = 0
    for i, band in ipairs(bands) do
        local start = math.floor(offset + 0.5)
        local stop = math.floor(offset + band_size + 0.5)
        offset = offset + band_size + gap
        if reserved > 0 and i == 1 then
            offset = offset + reserved
        end
        local along = layout.columns and h or w
        local cell_size = (along - gap * (#band - 1)) / #band
        for j, kind in ipairs(band) do
            local a = math.floor((j - 1) * (cell_size + gap) + 0.5)
            local b = math.floor((j - 1) * (cell_size + gap) + cell_size + 0.5)
            local cell = { kind = kind, band = i, index = j }
            if layout.columns then
                cell.x, cell.y, cell.w, cell.h = x + start, y + a, stop - start, b - a
            else
                cell.x, cell.y, cell.w, cell.h = x + a, y + start, b - a, stop - start
            end
            cells[#cells + 1] = cell
        end
    end
    if reserved > 0 then
        local top = cells[1]
        local bottom = cells[2]
        cells.bar = { x = x, y = top.y + top.h + gap, w = w, h = bottom.y - gap - (top.y + top.h + gap) }
    end
    return cells
end

-- Where each player sits, so the block faces them. Cells in a band of two face the sides when the
-- layout has three or more bands (or only one); otherwise the first band faces the top edge and the
-- last the bottom edge. Columns always face their side.
function Layouts.suggested_seats(layout)
    local seats = {}
    local n = #layout.bands
    for i, band in ipairs(layout.bands) do
        for j, kind in ipairs(band) do
            if kind == "p" then
                local seat
                if layout.columns then
                    seat = i == 1 and "left" or "right"
                elseif #band == 2 and (n >= 3 or n == 1) then
                    seat = j == 1 and "left" or "right"
                elseif i == 1 and n > 1 then
                    seat = "top"
                elseif i == n then
                    seat = "bottom"
                else
                    seat = (i - 0.5) / n < 0.5 and "top" or "bottom"
                end
                seats[#seats + 1] = seat
            end
        end
    end
    return seats
end

function Layouts.degrees(seat)
    return SEAT_DEGREES[seat] or 0
end

-- The two seats that see a cell wider than tall: for blocks designed only for landscape.
function Layouts.wide_seats(w, h)
    if w >= h then
        return { "bottom", "top" }
    end
    return { "left", "right" }
end

-- The seat after this one; with allowed, only among those (and the first one if seat is not there).
function Layouts.next_seat(seat, allowed)
    if allowed then
        for i, s in ipairs(allowed) do
            if s == seat then
                return allowed[i % #allowed + 1]
            end
        end
        return allowed[1]
    end
    for i, s in ipairs(SEAT_ORDER) do
        if s == seat then
            return SEAT_ORDER[i % #SEAT_ORDER + 1]
        end
    end
    return "bottom"
end

-- The size of a cell as its owner sees it.
function Layouts.local_size(w, h, seat)
    if seat == "left" or seat == "right" then
        return h, w
    end
    return w, h
end

-- Turns a point inside a cell (relative to its corner) into the owner's coordinates.
function Layouts.to_local(seat, w, h, px, py)
    if seat == "top" then
        return w - 1 - px, h - 1 - py
    elseif seat == "left" then
        return py, w - 1 - px
    elseif seat == "right" then
        return h - 1 - py, px
    end
    return px, py
end

-- And back, from the owner's coordinates to the cell.
function Layouts.from_local(seat, w, h, lx, ly)
    if seat == "top" then
        return w - 1 - lx, h - 1 - ly
    elseif seat == "left" then
        return w - 1 - ly, lx
    elseif seat == "right" then
        return ly, h - 1 - lx
    end
    return lx, ly
end

local function compositions(total, bands, allow_empty)
    local results = {}
    local function walk(prefix, remaining, empties)
        if #prefix == bands then
            if remaining == 0 then
                local copy = {}
                for i, band in ipairs(prefix) do
                    copy[i] = { band[1], band[2] }
                end
                results[#results + 1] = copy
            end
            return
        end
        local options = { { "p" }, { "p", "p" } }
        if allow_empty and empties == 0 then
            options[#options + 1] = { "p", "e" }
            options[#options + 1] = { "e", "p" }
        end
        for _, band in ipairs(options) do
            local players = 0
            for _, cell in ipairs(band) do
                if cell == "p" then
                    players = players + 1
                end
            end
            if players <= remaining then
                prefix[#prefix + 1] = band
                walk(prefix, remaining - players, empties + ((band[2] == "e" or band[1] == "e") and 1 or 0))
                prefix[#prefix] = nil
            end
        end
    end
    walk({}, total, 0)
    return results
end

-- Keeps the shapes people would pick: band sizes that mirror (1-2-1, 2-2) or step (1-2, 2-2-1), and an
-- empty cell only to complete a two-column grid, at the bottom right of a 2x2 or the middle of a 2x3.
local function shape_ok(layout)
    local sizes = {}
    for i, band in ipairs(layout.bands) do
        sizes[i] = #band
    end
    local n = #sizes
    if Layouts.has_empty(layout) then
        if layout.columns then
            return false
        end
        for _, size in ipairs(sizes) do
            if size ~= 2 then
                return false
            end
        end
        if n == 2 then
            return layout.bands[2][2] == "e"
        elseif n == 3 then
            return layout.bands[2][2] == "e"
        end
        return false
    end
    local mirror, up, down = true, true, true
    for i = 1, n do
        if sizes[i] ~= sizes[n - i + 1] then
            mirror = false
        end
        if i > 1 and sizes[i] < sizes[i - 1] then
            up = false
        end
        if i > 1 and sizes[i] > sizes[i - 1] then
            down = false
        end
    end
    return mirror or up or down
end

local function fits(layout, w, h)
    local limit = MIN_SIDE * math.min(w, h)
    for _, cell in ipairs(Layouts.rects(layout, 0, 0, w, h, 8, 56)) do
        if math.min(cell.w, cell.h) < limit then
            return false
        end
    end
    return true
end

local function signature(layout, w, h)
    local parts = {}
    for _, cell in ipairs(Layouts.rects(layout, 0, 0, w, h, 0)) do
        parts[#parts + 1] = string.format("%s%d,%d,%d,%d", cell.kind, cell.x, cell.y, cell.w, cell.h)
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

local function score(layout)
    local value = #layout.bands * 10 + (layout.columns and 3 or 0) + (Layouts.has_empty(layout) and 50 or 0)
    if layout.id == Layouts.BAR then
        value = value - 100
    end
    return value
end

-- Every layout for a number of players that fits a screen of w x h, simplest first.
function Layouts.for_players(n, w, h)
    w, h = w or 600, h or 800
    local found, seen = {}, {}
    for _, columns in ipairs({ false, true }) do
        local max_bands = columns and 2 or MAX_BANDS
        local min_bands = columns and 2 or 1
        for bands = min_bands, max_bands do
            for _, candidate in ipairs(compositions(n, bands, true)) do
                local layout = { columns = columns, bands = candidate }
                layout.id = Layouts.encode(layout)
                local key = signature(layout, w, h)
                if not seen[key] and Layouts.players(layout) == n and shape_ok(layout) and fits(layout, w, h) then
                    seen[key] = true
                    found[#found + 1] = layout
                end
            end
        end
    end
    table.sort(found, function(a, b)
        local sa, sb = score(a), score(b)
        if sa ~= sb then
            return sa < sb
        end
        return a.id < b.id
    end)
    return found
end

return Layouts
