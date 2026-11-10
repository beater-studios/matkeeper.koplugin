local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local RenderImage = require("ui/renderimage")
local TextWidget = require("ui/widget/textwidget")

local Screen = Device.screen

-- Drawing helpers: colors, fonts sized in pixels, shapes, icon masks and pictures. Everything is
-- painted straight into a blitbuffer, which may be rotated, so the same code serves every seat.
local Draw = {}

Draw.BLACK = Blitbuffer.COLOR_BLACK
Draw.WHITE = Blitbuffer.COLOR_WHITE
Draw.INK = Blitbuffer.Color8(0x22)
Draw.DARK = Blitbuffer.Color8(0x44)
Draw.MID = Blitbuffer.Color8(0x88)
Draw.LIGHT = Blitbuffer.Color8(0xBB)
Draw.PALE = Blitbuffer.Color8(0xDD)
Draw.PAPER = Blitbuffer.Color8(0xEE)

local FONTS = {
    sans = "NotoSans-Regular.ttf",
    bold = "NotoSans-Bold.ttf",
    serif = "noto/NotoSerif-Bold.ttf",
    italic = "noto/NotoSerif-Italic.ttf",
}

local assets_dir = "."
local masks, pictures = {}, {}

function Draw.init(plugin_dir)
    assets_dir = plugin_dir .. "/assets"
end

-- Sizes are designed for a 600 x 800 screen and scaled to the real one.
function Draw.unit()
    return math.min(Screen:getWidth(), Screen:getHeight()) / 600
end

function Draw.s(value)
    return math.floor(value * Draw.unit() + 0.5)
end

-- A font face whose size is in pixels, undoing the scaling KOReader applies by screen density.
function Draw.face(name, px)
    local factor = Screen:scaleBySize(1000) / 1000
    return Font:getFace(FONTS[name] or name, math.max(6, px / factor))
end

function Draw.rect(bb, x, y, w, h, color, radius)
    if w <= 0 or h <= 0 then
        return
    end
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    if radius and radius > 0 then
        bb:paintRoundedRect(x, y, w, h, color, math.floor(math.min(radius, w / 2, h / 2)))
    else
        bb:paintRect(x, y, w, h, color)
    end
end

function Draw.border(bb, x, y, w, h, size, color, radius)
    if w <= 0 or h <= 0 then
        return
    end
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    bb:paintBorder(x, y, w, h, math.max(1, math.floor(size + 0.5)), color, radius and math.floor(math.min(radius, w / 2, h / 2)) or nil)
end

function Draw.circle(bb, cx, cy, r, color)
    bb:paintCircle(math.floor(cx), math.floor(cy), math.floor(r), color)
end

function Draw.ring(bb, cx, cy, r, width, color)
    bb:paintCircle(math.floor(cx), math.floor(cy), math.floor(r), color, math.max(1, math.floor(width + 0.5)))
end

function Draw.hline(bb, x, y, w, size, color)
    bb:paintRect(math.floor(x), math.floor(y), math.floor(w), math.max(1, math.floor(size + 0.5)), color)
end

local function load(path, w, h)
    local image = RenderImage:renderImageFile(path, false, w, h)
    if not image then
        return nil
    end
    local gray = Blitbuffer.new(image:getWidth(), image:getHeight(), Blitbuffer.TYPE_BB8)
    gray:blitFrom(image)
    image:free()
    return gray
end

-- Paints an icon mask in a color, centered in a square of side size.
function Draw.icon(bb, name, cx, cy, size, color)
    size = math.max(4, math.floor(size + 0.5))
    local key = name .. "@" .. size
    local mask = masks[key]
    if mask == nil then
        mask = load(assets_dir .. "/icons/" .. name .. ".png", size, size) or false
        masks[key] = mask
    end
    if mask then
        bb:colorblitFrom(mask, math.floor(cx - size / 2), math.floor(cy - size / 2), 0, 0, size, size, color or Draw.BLACK)
    end
end

-- An icon turned to face a seat (the masks are drawn for "bottom").
function Draw.icon_turned(bb, name, cx, cy, size, color, degrees)
    if not degrees or degrees == 0 then
        return Draw.icon(bb, name, cx, cy, size, color)
    end
    size = math.max(4, math.floor(size + 0.5))
    local tmp = Blitbuffer.new(size, size, bb:getType())
    tmp:blitFrom(bb, 0, 0, math.floor(cx - size / 2), math.floor(cy - size / 2), size, size)
    tmp:rotateAbsolute(degrees)
    Draw.icon(tmp, name, size / 2, size / 2, size, color)
    tmp:rotateAbsolute(0)
    bb:blitFrom(tmp, math.floor(cx - size / 2), math.floor(cy - size / 2), 0, 0, size, size)
    tmp:free()
end

-- Paints a picture (assets/<path>) fitted to w x h, centered on (cx, cy). Returns its size.
function Draw.picture(bb, path, cx, cy, w, h)
    local key = path .. "@" .. math.floor(w) .. "x" .. math.floor(h or 0)
    local image = pictures[key]
    if image == nil then
        local full = assets_dir .. "/" .. path
        if h then
            local probe = load(full)
            if probe then
                local scale = math.min(w / probe:getWidth(), h / probe:getHeight())
                local tw, th = math.max(1, math.floor(probe:getWidth() * scale)), math.max(1, math.floor(probe:getHeight() * scale))
                probe:free()
                image = load(full, tw, th) or false
            else
                image = false
            end
        else
            image = load(full, math.floor(w)) or false
        end
        pictures[key] = image
    end
    if not image then
        return 0, 0
    end
    local iw, ih = image:getWidth(), image:getHeight()
    bb:blitFrom(image, math.floor(cx - iw / 2), math.floor(cy - ih / 2), 0, 0, iw, ih)
    return iw, ih
end

function Draw.free()
    for _, cache in ipairs({ masks, pictures }) do
        for key, image in pairs(cache) do
            if image then
                image:free()
            end
            cache[key] = nil
        end
    end
end

function Draw.text_width(text, face)
    local widget = TextWidget:new{ text = text, face = face }
    local w = widget:getSize().w
    widget:free()
    return w
end

-- Text inside a box: align is "left", "right" or "center" (default), vertically centered.
function Draw.text(bb, text, face, x, y, w, h, align, color)
    if not text or text == "" then
        return 0
    end
    local widget = TextWidget:new{ text = text, face = face, fgcolor = color or Draw.BLACK, max_width = math.max(1, math.floor(w)) }
    local size = widget:getSize()
    local px = x
    if align == "right" then
        px = x + w - size.w
    elseif align ~= "left" then
        px = x + (w - size.w) / 2
    end
    widget:paintTo(bb, math.floor(px), math.floor(y + (h - size.h) / 2))
    widget:free()
    return size.w
end

-- Text wrapped to a width, line by line. Returns the height used.
function Draw.paragraph(bb, text, face, x, y, w, line_h, color, align)
    local lines = Draw.wrap(text, face, w)
    for i, line in ipairs(lines) do
        Draw.text(bb, line, face, x, y + (i - 1) * line_h, w, line_h, align or "left", color)
    end
    return #lines * line_h
end

function Draw.wrap(text, face, w)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        local trial = line == "" and word or (line .. " " .. word)
        if line ~= "" and Draw.text_width(trial, face) > w then
            lines[#lines + 1] = line
            line = word
        else
            line = trial
        end
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

---------------------------------------------------------------------------
-- The look: framed cards, pills, chips and buttons.
---------------------------------------------------------------------------

-- A white card with a thin inner frame, on the table color.
function Draw.card(bb, x, y, w, h, thick, fill)
    local r = Draw.s(16)
    Draw.rect(bb, x, y, w, h, fill or Draw.WHITE, r)
    local inset = Draw.s(5)
    Draw.border(bb, x + inset, y + inset, w - 2 * inset, h - 2 * inset, thick and Draw.s(3) or math.max(1, Draw.s(1.5)), Draw.BLACK, r - Draw.s(4))
end

function Draw.pill(bb, x, y, w, h, fill, outline, line)
    Draw.rect(bb, x, y, w, h, fill, h / 2)
    if outline then
        Draw.border(bb, x, y, w, h, line or math.max(1, Draw.s(1.5)), outline, h / 2)
    end
end

-- A big rounded button. style: "filled", "outline" or "disabled".
function Draw.button(bb, x, y, w, h, text, style, px)
    local face = Draw.face("bold", px or Draw.s(18))
    if style == "disabled" then
        Draw.pill(bb, x, y, w, h, Draw.PALE)
        Draw.text(bb, text, face, x, y, w, h, "center", Draw.MID)
    elseif style == "outline" then
        Draw.pill(bb, x, y, w, h, Draw.WHITE, Draw.BLACK, Draw.s(2))
        Draw.text(bb, text, face, x, y, w, h, "center", Draw.BLACK)
    else
        Draw.pill(bb, x + Draw.s(3), y + Draw.s(4), w, h, Draw.MID)
        Draw.pill(bb, x, y, w, h, Draw.INK)
        Draw.text(bb, text, face, x, y, w, h, "center", Draw.WHITE)
    end
end

-- A small rounded label with an optional icon. Returns its width.
function Draw.chip(bb, x, cy, h, icon, text, opts)
    opts = opts or {}
    local face = opts.face or Draw.face("bold", h * 0.5)
    local pad = h * 0.35
    local icon_s = icon and h * 0.55 or 0
    local width = pad + (icon and icon_s + h * 0.2 or 0) + Draw.text_width(text, face) + pad
    if opts.measure then
        return width
    end
    local fill, ink = opts.fill or Draw.PAPER, opts.ink or Draw.BLACK
    Draw.pill(bb, x, cy - h / 2, width, h, fill, opts.outline or ink, math.max(1, Draw.s(1.2)))
    local tx = x + pad
    if icon then
        Draw.icon(bb, icon, tx + icon_s / 2, cy, icon_s, ink)
        tx = tx + icon_s + h * 0.2
    end
    Draw.text(bb, text, face, tx, cy - h / 2, width, h, "left", ink)
    return width
end

-- A round button with an icon.
function Draw.round_button(bb, cx, cy, r, icon, fill, ink, outline)
    Draw.circle(bb, cx, cy, r, fill or Draw.WHITE)
    if outline then
        Draw.ring(bb, cx, cy, r, Draw.s(2), outline)
    end
    Draw.icon(bb, icon, cx, cy, r * 1.05, ink or Draw.BLACK)
end

function Draw.check_badge(bb, cx, cy, r)
    Draw.circle(bb, cx, cy, r, Draw.WHITE)
    Draw.circle(bb, cx, cy, r - Draw.s(3), Draw.INK)
    Draw.icon(bb, "check", cx, cy, r * 1.1, Draw.WHITE)
end

return Draw
