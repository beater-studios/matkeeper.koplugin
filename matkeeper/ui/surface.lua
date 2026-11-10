local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")

local Draw = require("matkeeper/ui/draw")
local Layouts = require("matkeeper/layouts")

local Screen = Device.screen

-- The whole screen as a set of panes. Each pane is a rectangle of the screen with a seat: its view
-- is drawn in the owner's orientation into a buffer of its own, turned to face that seat, and kept
-- until it changes. Touches are turned back into the owner's coordinates, so every view works the
-- same at any rotation. A modal pane can sit on top, with the rest of the screen darkened.
--
-- A view is a table with draw(view, ctx), where ctx.bb is the buffer, ctx.w and ctx.h its size as
-- the owner sees it, and ctx:hit(x, y, w, h, tap, hold) marks a touch area.
local Surface = InputContainer:extend{
    name = "matkeeper_surface",
    covers_fullscreen = true,
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
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
        Hold = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end

function Surface:getSize()
    return self.dimen
end

-- Draws a pane into a buffer of its own. A base buffer (a copy of what is under the pane) makes it
-- transparent: the view draws over the screen instead of over a blank rectangle.
local function render(pane, base)
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
    pane.view:draw(ctx)
    bb:rotateAbsolute(0)
    pane.bb = bb
    pane.hits = ctx.hits
    pane.dirty = false
end

-- panes: { { x, y, w, h, seat, view, fill } }. Replaces everything (and closes the modal).
function Surface:set_panes(panes, refresh)
    self:free_panes()
    self.panes = panes
    for _, pane in ipairs(panes) do
        pane.dirty = true
    end
    self.modal = nil
    self:refresh(nil, refresh or "ui")
end

function Surface:free_panes()
    for _, pane in ipairs(self.panes or {}) do
        if pane.bb then
            pane.bb:free()
            pane.bb = nil
        end
    end
    if self.modal and self.modal.bb then
        self.modal.bb:free()
        self.modal.bb = nil
    end
end

-- Redraws one pane (or all, or the modal) and refreshes only its rectangle.
function Surface:update(pane, mode)
    if pane then
        pane.dirty = true
        self:refresh(pane, mode or "ui")
    else
        for _, p in ipairs(self.panes) do
            p.dirty = true
        end
        if self.modal then
            self.modal.dirty = true
        end
        self:refresh(nil, mode or "ui")
    end
end

function Surface:refresh(pane, mode)
    local region = pane and Geom:new{ x = pane.x, y = pane.y, w = pane.w, h = pane.h } or self.dimen
    UIManager:setDirty(self, function()
        return mode or "ui", region
    end)
end

-- A modal pane over the screen, facing a seat. Taps outside its hit areas call on_outside.
function Surface:show_modal(view, seat, on_outside)
    if self.modal and self.modal.bb then
        self.modal.bb:free()
    end
    self.modal = { x = 0, y = 0, w = self.dimen.w, h = self.dimen.h, seat = seat or "bottom", view = view, dirty = true, on_outside = on_outside, transparent = true }
    self:refresh(nil, "ui")
end

function Surface:close_modal()
    if self.modal then
        if self.modal.bb then
            self.modal.bb:free()
        end
        self.modal = nil
        self:refresh(nil, "ui")
    end
end

function Surface:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, self.background)
    for _, pane in ipairs(self.panes) do
        if pane.transparent then
            local base = Blitbuffer.new(pane.w, pane.h, bb:getType())
            base:blitFrom(bb, 0, 0, x + pane.x, y + pane.y, pane.w, pane.h)
            render(pane, base)
        elseif pane.dirty or not pane.bb then
            render(pane)
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
            modal.view:draw(ctx)
            copy:rotateAbsolute(0)
            if modal.bb then
                modal.bb:free()
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

function Surface:dispatch(ges, kind)
    local gx, gy = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    if self.modal then
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
