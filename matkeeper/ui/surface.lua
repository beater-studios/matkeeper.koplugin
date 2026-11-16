local Blitbuffer = require("ffi/blitbuffer")
local ffi = require("ffi")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Draw = require("matkeeper/ui/draw")
local Layouts = require("matkeeper/layouts")
local Refresh = require("matkeeper/refresh")
local Sleep = require("matkeeper/sleep")

local Screen = Device.screen

pcall(require, "ffi/posix_h")
if not pcall(function() return ffi.C.memcmp end) then
    ffi.cdef("int memcmp(const void *, const void *, size_t);")
end

-- Where two drawings of the screen differ: a rectangle, false when they are the same, or nil when they
-- cannot be compared (another size or type). The memory is read directly, a row at a time: reading pixel
-- by pixel is slow on the device. The rows in memory do not depend on how the buffers were rotated.
local function changed_rect(a, b)
    local w, h, stride = a.w, a.h, tonumber(a.stride)
    if b.w ~= w or b.h ~= h or tonumber(b.stride) ~= stride or a:getType() ~= b:getType() then
        return nil
    end
    local bpp = stride / a.pixel_stride
    local row_bytes = w * bpp
    local pa, pb = ffi.cast("uint8_t *", a.data), ffi.cast("uint8_t *", b.data)
    local function same_row(y)
        return ffi.C.memcmp(pa + y * stride, pb + y * stride, row_bytes) == 0
    end
    local top = 0
    while top < h and same_row(top) do
        top = top + 1
    end
    if top == h then
        return false
    end
    local bottom = h - 1
    while same_row(bottom) do
        bottom = bottom - 1
    end
    local left, right = w, -1
    for y = top, bottom do
        local ra, rb = pa + y * stride, pb + y * stride
        local i = 0
        while i < left * bpp and ra[i] == rb[i] do
            i = i + 1
        end
        if i < left * bpp then
            left = math.floor(i / bpp)
        end
        local j = row_bytes - 1
        while j >= (right + 1) * bpp and ra[j] == rb[j] do
            j = j - 1
        end
        if j >= (right + 1) * bpp then
            right = math.floor(j / bpp)
        end
    end
    -- A little margin: the e-ink driver ignores a region 1 pixel wide or high.
    local x0, y0 = math.max(0, left - 2), math.max(0, top - 2)
    local x1, y1 = math.min(w, right + 3), math.min(h, bottom + 3)
    return Geom:new{ x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

-- The whole screen as a set of panes. Each pane is a rectangle of the screen with a seat: its view
-- is drawn in the owner's orientation into a buffer of its own, turned to face that seat, and kept
-- until it changes. Touches are turned back into the owner's coordinates, so every view works the
-- same at any rotation. A modal pane can sit on top, with the rest of the screen darkened.
--
-- A view is a table with draw(view, ctx), where ctx.bb is the buffer, ctx.w and ctx.h its size as
-- the owner sees it, and ctx:hit(x, y, w, h, tap, hold) marks a touch area. A view that fails to
-- draw leaves its pane to paint_failed, so the rest of the screen still works.
local Surface = InputContainer:extend{
    name = "matkeeper_surface",
    covers_fullscreen = true,
    stop_events_propagation = true,
    background = nil,
}

local DEGREES = { bottom = 0, left = 90, top = 180, right = 270 }

local Context = {}
Context.__index = Context

function Context:hit(x, y, w, h, tap, hold)
    self.hits[#self.hits + 1] = { x = x, y = y, w = w, h = h, tap = tap, hold = hold }
end

function Surface:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.panes = {}
    self.modal = nil
    self.background = self.background or Draw.INK
    Sleep.watch(self)
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
        Hold = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end

function Surface:getSize()
    return self.dimen
end

-- Runs the view of a pane; if it fails, the pane is cleared and handed to paint_failed instead, so an
-- error does not come back on every paint and lock the screen.
local function draw_view(surface, pane, ctx)
    local ok, err = pcall(pane.view.draw, pane.view, ctx)
    if not ok then
        logger.warn("matkeeper: could not draw a pane", err)
        ctx.hits = {}
        ctx.bb:paintRect(0, 0, ctx.w, ctx.h, Draw.WHITE)
        pcall(surface.paint_failed, surface, ctx)
    end
end

-- Draws a pane into a buffer of its own. A base buffer (a copy of what is under the pane) makes it
-- transparent: the view draws over the screen instead of over a blank rectangle.
local function render(surface, pane, base)
    local seat = pane.seat or "bottom"
    if pane.bb then
        pane.bb:free()
    end
    local bb = base or Blitbuffer.new(pane.w, pane.h, Screen.bb:getType())
    bb:rotateAbsolute(DEGREES[seat])
    local lw, lh = bb:getWidth(), bb:getHeight()
    if pane.fill then
        bb:paintRect(0, 0, lw, lh, pane.fill)
    end
    local ctx = setmetatable({ bb = bb, w = lw, h = lh, hits = {}, pane = pane }, Context)
    draw_view(surface, pane, ctx)
    bb:rotateAbsolute(0)
    pane.bb = bb
    pane.hits = ctx.hits
    pane.dirty = false
end

-- panes: { { x, y, w, h, seat, view, fill } }. Replaces everything (and closes the modal). kind names
-- what the panes show (a page, the table), for refresh_mode.
function Surface:set_panes(panes, kind)
    self:free_panes()
    self.panes = panes
    for _, pane in ipairs(panes) do
        pane.dirty = true
    end
    self.modal = nil
    self.kind = kind
    self:refresh(nil)
end

-- For a failed pane: ctx is cleared to white, with no touch areas. The screen draws its message here.
function Surface:paint_failed(ctx)
end

-- The refresh mode of a change when the caller does not name one. The screen counts them. inside is
-- true for a change inside an open dialog, refreshed only where its drawing changed.
function Surface:refresh_mode(inside)
    return "ui"
end

function Surface:free_panes()
    for _, pane in ipairs(self.panes or {}) do
        if pane.bb then
            pane.bb:free()
            pane.bb = nil
        end
    end
    if self.modal then
        for _, key in ipairs({ "bb", "previous_bb" }) do
            if self.modal[key] then
                self.modal[key]:free()
                self.modal[key] = nil
            end
        end
    end
end

-- Redraws one pane (or all, or the modal) and refreshes only its rectangle. Behind an open dialog the
-- panes keep their drawing until it closes: they are covered, and redrawing them would change the
-- darkened screen the dialog is drawn on, so a change inside the dialog would refresh it all.
function Surface:update(pane, mode)
    if self.modal then
        for _, p in ipairs(pane and { pane } or self.panes) do
            p.behind = true
        end
        return
    end
    if pane then
        pane.dirty = true
        self:refresh(pane, mode)
    else
        for _, p in ipairs(self.panes) do
            p.dirty = true
        end
        if self.modal then
            self.modal.dirty = true
        end
        self:refresh(nil, mode)
    end
end

-- A full refresh always takes the whole screen, so the ghosting of the rest goes too. Nothing is
-- refreshed while the device sleeps: the window is repainted when it wakes up. The mode and the area are
-- worked out when KOReader asks for them, after painting, so a dialog drawn again (inside) refreshes only
-- the rectangle that changed.
function Surface:refresh(pane, mode, inside)
    Sleep.dirty(self, function()
        local region
        if inside then
            local changed = self.modal and self.modal.changed
            if changed then
                region = changed
            elseif changed == false then
                -- Nothing changed: a region the e-ink driver ignores, so KOReader does not refresh it all.
                region = Geom:new{ x = 0, y = 0, w = 1, h = 1 }
            else
                inside = false
            end
        end
        local m = mode or self:refresh_mode(inside)
        if m == "full" or not region then
            region = pane and m ~= "full" and Geom:new{ x = pane.x, y = pane.y, w = pane.w, h = pane.h } or self.dimen
        end
        return Refresh.settle(m), region
    end)
end

-- A modal pane over the screen, facing a seat. Taps outside its hit areas call on_outside. Over another
-- dialog (most often the same one, drawn again after a tap), the drawing on screen is kept to compare
-- with the new one, so only what changed is refreshed.
function Surface:show_modal(view, seat, on_outside)
    local previous = self.modal
    local on_screen
    if previous then
        -- A dialog replaced before it was ever painted passes on the drawing that is still on screen.
        on_screen = previous.bb or previous.previous_bb
        if previous.bb and previous.previous_bb then
            previous.previous_bb:free()
        end
    end
    self.modal = { x = 0, y = 0, w = self.dimen.w, h = self.dimen.h, seat = seat or "bottom", view = view, dirty = true, on_outside = on_outside, transparent = true, previous_bb = on_screen }
    self:refresh(nil, nil, on_screen ~= nil)
end

function Surface:close_modal()
    if self.modal then
        for _, key in ipairs({ "bb", "previous_bb" }) do
            if self.modal[key] then
                self.modal[key]:free()
            end
        end
        self.modal = nil
        for _, pane in ipairs(self.panes) do
            if pane.behind then
                pane.behind = nil
                pane.dirty = true
            end
        end
        self:refresh(nil)
    end
end

function Surface:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, self.background)
    for _, pane in ipairs(self.panes) do
        if pane.transparent then
            local base = Blitbuffer.new(pane.w, pane.h, bb:getType())
            base:blitFrom(bb, 0, 0, x + pane.x, y + pane.y, pane.w, pane.h)
            render(self, pane, base)
        elseif pane.dirty or not pane.bb then
            render(self, pane)
        end
        bb:blitFrom(pane.bb, x + pane.x, y + pane.y, 0, 0, pane.w, pane.h)
    end
    local modal = self.modal
    if modal then
        bb:darkenRect(x, y, self.dimen.w, self.dimen.h, 0.45)
        if modal.dirty or not modal.bb then
            modal.fill = nil
            -- The modal draws on a copy of the darkened screen, so only its box covers it.
            local seat = modal.seat
            local copy = Blitbuffer.new(modal.w, modal.h, Screen.bb:getType())
            copy:blitFrom(bb, 0, 0, x, y, modal.w, modal.h)
            copy:rotateAbsolute(DEGREES[seat])
            local ctx = setmetatable({ bb = copy, w = copy:getWidth(), h = copy:getHeight(), hits = {}, pane = modal }, Context)
            draw_view(self, modal, ctx)
            copy:rotateAbsolute(0)
            if modal.bb then
                modal.bb:free()
            end
            if modal.previous_bb then
                modal.changed = changed_rect(modal.previous_bb, copy)
                modal.previous_bb:free()
                modal.previous_bb = nil
            end
            modal.bb = copy
            modal.hits = ctx.hits
            modal.dirty = false
        end
        bb:blitFrom(modal.bb, x, y, 0, 0, modal.w, modal.h)
    end
end

local function find(pane, gx, gy)
    if gx < pane.x or gy < pane.y or gx >= pane.x + pane.w or gy >= pane.y + pane.h then
        return nil
    end
    local lx, ly = Layouts.to_local(pane.seat or "bottom", pane.w, pane.h, gx - pane.x, gy - pane.y)
    local hits = pane.hits or {}
    for i = #hits, 1, -1 do
        local h = hits[i]
        if lx >= h.x and ly >= h.y and lx < h.x + h.w and ly < h.y + h.h then
            return h, lx, ly
        end
    end
    return false
end

-- True when the modal or a pane has never been painted, so it has no touch areas yet.
local function unpainted(surface)
    if surface.modal and not surface.modal.hits then
        return true
    end
    for _, pane in ipairs(surface.panes) do
        if not pane.hits then
            return true
        end
    end
    return false
end

function Surface:dispatch(ges, kind)
    -- KOReader handles a whole batch of queued touches before it paints. A dialog reopened by the previous
    -- touch of the batch has no touch areas yet, and a tap on it counted as a tap outside, closing it. So
    -- what was never painted is painted first, and the tap lands on what the player sees.
    if unpainted(self) then
        UIManager:forceRePaint()
    end
    local gx, gy = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    if self.modal then
        -- Still unpainted (asleep, or covered by another window): the tap is dropped, never taken as outside.
        if not self.modal.hits then
            return true
        end
        local hit, lx, ly = find(self.modal, gx, gy)
        local action = hit and (hit[kind] or (kind == "hold" and hit.tap))
        if action then
            action(lx - hit.x, ly - hit.y)
        elseif not hit and kind == "tap" and self.modal.on_outside then
            self.modal.on_outside()
        end
        return true
    end
    for i = #self.panes, 1, -1 do
        local hit, lx, ly = find(self.panes[i], gx, gy)
        if hit then
            local action = hit[kind] or (kind == "hold" and hit.tap)
            if action then
                action(lx - hit.x, ly - hit.y)
            end
            return true
        elseif hit == false then
            return true
        end
    end
    return true
end

function Surface:onTap(_, ges)
    return self:dispatch(ges, "tap")
end

function Surface:onHold(_, ges)
    return self:dispatch(ges, "hold")
end

function Surface:onCloseWidget()
    self:free_panes()
end

return Surface
