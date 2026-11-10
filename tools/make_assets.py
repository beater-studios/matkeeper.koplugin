"""Draws the plugin's images with Pillow: icon masks, coins, dice, the home banner, the sleep screen
cover and the logos.

Usage: make_assets.py <output assets dir> [<logo sources dir>]
BOLD_FONT points to NotoSans-Bold.ttf from KOReader; NotoSerif-Bold.ttf next to it draws the title.

Icons are masks (white shape on black): the plugin paints them in any color and at any rotation.
Coins, dice and the banner are grayscale pictures on white or on the table color. Everything is
reduced to the 16 gray levels of the screen. Logo sources (magic.png, pokemon.png) are optional;
without them the logos already in the output folder are kept.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont, ImageOps

OUT = sys.argv[1]
LOGO_SOURCES = sys.argv[2] if len(sys.argv) > 2 else None
SS = 4
BLACK, INK, DARK, MID, LIGHT, PALE, PAPER, WHITE = 0, 34, 68, 136, 187, 221, 238, 255
ICON = 96


class Pen:
    def __init__(self, w, h, bg):
        self.w, self.h = w, h
        self.image = Image.new("L", (w * SS, h * SS), bg)
        self.d = ImageDraw.Draw(self.image)

    def s(self, v):
        return round(v * SS)

    def pts(self, points):
        return [(self.s(x), self.s(y)) for x, y in points]

    def poly(self, points, fill):
        self.d.polygon(self.pts(points), fill=fill)

    def line(self, points, fill, width):
        self.d.line(self.pts(points), fill=fill, width=self.s(width), joint="curve")

    def circle(self, cx, cy, r, fill=None, outline=None, width=0):
        self.d.ellipse([self.s(cx - r), self.s(cy - r), self.s(cx + r), self.s(cy + r)], fill=fill, outline=outline,
                       width=self.s(width) if outline is not None else 0)

    def rect(self, x0, y0, x1, y1, fill=None, outline=None, width=0, radius=0):
        self.d.rounded_rectangle([self.s(x0), self.s(y0), self.s(x1), self.s(y1)], radius=self.s(radius), fill=fill,
                                 outline=outline, width=self.s(width) if outline is not None else 0)

    def arc(self, cx, cy, r, start, end, fill, width):
        self.d.arc([self.s(cx - r), self.s(cy - r), self.s(cx + r), self.s(cy + r)], start, end, fill=fill, width=self.s(width))

    def text(self, x, y, value, face, fill):
        self.d.text((self.s(x), self.s(y)), value, font=face, fill=fill, anchor="mm")

    def save(self, path, levels=True):
        small = self.image.resize((self.w, self.h), Image.LANCZOS)
        if levels:
            small = small.point(lambda v: round(v / 17) * 17)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        small.save(path, optimize=True)


# Icons, drawn around (c, c) in a box of side s, in the given fill.

def heart(p, c, s, f):
    pts = []
    for i in range(72):
        t = 2 * math.pi * i / 72
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((c + x * s / 34, c - y * s / 34 - s * 0.05))
    p.poly(pts, f)


def drop(p, c, s, f):
    r = s / 2
    pts = []
    for i in range(72):
        t = 2 * math.pi * i / 72
        pts.append((c + r * 0.8 * math.sin(t) * math.sin(t / 2), c - r * math.cos(t)))
    p.poly(pts, f)


def flame(p, c, s, f):
    shape = [(0, -0.5), (0.13, -0.18), (0.24, -0.34), (0.36, -0.04), (0.38, 0.2), (0.27, 0.4), (0.08, 0.5),
             (-0.12, 0.5), (-0.3, 0.38), (-0.38, 0.16), (-0.33, -0.08), (-0.2, 0.06), (-0.14, -0.24)]
    p.poly([(c + x * s, c + y * s) for x, y in shape], f)


def crown(p, c, s, f):
    w, h = s, s * 0.75
    x0, y0 = c - w / 2, c - h / 2
    p.poly([(x0, y0 + h * 0.25), (x0 + w * 0.27, y0 + h * 0.55), (x0 + w * 0.5, y0), (x0 + w * 0.73, y0 + h * 0.55),
            (x0 + w, y0 + h * 0.25), (x0 + w * 0.88, y0 + h * 0.85), (x0 + w * 0.12, y0 + h * 0.85)], f)
    p.rect(x0 + w * 0.12, y0 + h * 0.9, x0 + w * 0.88, y0 + h, fill=f)


def shield(p, c, s, f):
    w, h = s * 0.8, s
    x0, y0 = c - w / 2, c - h / 2
    p.poly([(x0, y0 + h * 0.12), (c, y0), (x0 + w, y0 + h * 0.12), (x0 + w, y0 + h * 0.5), (c, y0 + h), (x0, y0 + h * 0.5)], f)


def star(p, c, s, f, cx=None, cy=None):
    cx = c if cx is None else cx
    cy = c if cy is None else cy
    pts = []
    for i in range(10):
        r = s / 2 if i % 2 == 0 else s / 5
        a = math.radians(-90 + i * 36)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    p.poly(pts, f)


def bolt(p, c, s, f):
    p.poly([(c + s * 0.1, c - s * 0.5), (c - s * 0.3, c + s * 0.08), (c - s * 0.02, c + s * 0.08), (c - s * 0.12, c + s * 0.5),
            (c + s * 0.3, c - s * 0.1), (c + s * 0.02, c - s * 0.1)], f)


def sleep(p, c, s, f, font_path):
    p.text(c - s * 0.12, c + s * 0.08, "Z", ImageFont.truetype(font_path, p.s(s * 0.62)), f)
    p.text(c + s * 0.26, c - s * 0.2, "z", ImageFont.truetype(font_path, p.s(s * 0.42)), f)


def spiral(p, c, s, f):
    pts = []
    for i in range(100):
        t = i / 100 * 4 * math.pi
        r = s * 0.48 * i / 100
        pts.append((c + r * math.cos(t), c + r * math.sin(t)))
    p.line(pts, f, s * 0.1)


def menu(p, c, s, f):
    for dy in (-0.3, 0, 0.3):
        p.line([(c - s * 0.38, c + dy * s), (c + s * 0.38, c + dy * s)], f, s * 0.12)


def undo(p, c, s, f):
    r = s * 0.34
    p.arc(c + s * 0.05, c + s * 0.05, r, 180, 90, f, s * 0.12)
    p.poly([(c - r - s * 0.24, c + s * 0.02), (c - r + s * 0.22, c + s * 0.02), (c - r + s * 0.05, c - s * 0.26)], f)


def rotate(p, c, s, f):
    r = s * 0.36
    p.arc(c, c, r, 300, 210, f, s * 0.11)
    a = math.radians(300)
    ex, ey = c + r * math.cos(a), c + r * math.sin(a)
    p.poly([(ex - s * 0.2, ey - s * 0.1), (ex + s * 0.14, ey - s * 0.16), (ex + s * 0.02, ey + s * 0.18)], f)


def clock(p, c, s, f):
    p.circle(c, c, s / 2, outline=f, width=s * 0.1)
    p.line([(c, c), (c, c - s * 0.3)], f, s * 0.09)
    p.line([(c, c), (c + s * 0.22, c)], f, s * 0.09)


def check(p, c, s, f):
    p.line([(c - s * 0.35, c), (c - s * 0.08, c + s * 0.28), (c + s * 0.38, c - s * 0.3)], f, s * 0.16)


def sun(p, c, s, f):
    p.circle(c, c, s * 0.22, fill=f)
    for i in range(8):
        a = math.radians(i * 45)
        p.line([(c + s * 0.32 * math.cos(a), c + s * 0.32 * math.sin(a)), (c + s * 0.48 * math.cos(a), c + s * 0.48 * math.sin(a))], f, s * 0.09)


def moon(p, c, s, f):
    p.circle(c, c, s * 0.42, fill=f)
    p.circle(c + s * 0.2, c - s * 0.12, s * 0.36, fill=0)


def chevron(direction):
    def draw(p, c, s, f):
        d = 1 if direction == "right" else -1
        p.line([(c - d * s * 0.18, c - s * 0.35), (c + d * s * 0.18, c), (c - d * s * 0.18, c + s * 0.35)], f, s * 0.14)
    return draw


def triangle(p, c, s, f):
    p.poly([(c, c + s * 0.42), (c - s * 0.42, c - s * 0.2), (c + s * 0.42, c - s * 0.2)], f)


def d20(p, c, s, f):
    r = s / 2
    hexagon = [(c + r * math.cos(math.radians(a)), c + r * math.sin(math.radians(a))) for a in range(-90, 270, 60)]
    p.poly(hexagon, f)
    inner = [(c, c - r * 0.62), (c + r * 0.62, c + r * 0.42), (c - r * 0.62, c + r * 0.42)]
    p.poly(inner, 0)
    for corner, target in ((0, 0), (1, 1), (2, 1), (3, 2), (4, 2), (5, 0)):
        p.line([hexagon[corner], inner[target]], 0, s / 30)


def coins(p, c, s, f):
    for dx, dy in ((-s * 0.14, s * 0.1), (s * 0.14, -s * 0.06)):
        p.circle(c + dx, c + dy, s * 0.3, fill=0)
        p.circle(c + dx, c + dy, s * 0.26, outline=f, width=s * 0.07)
    star(p, c, s * 0.24, f, c + s * 0.14, c - s * 0.06)


def coin_mask(p, c, s, f):
    p.circle(c, c, s * 0.46, fill=f)
    p.circle(c, c, s * 0.34, outline=0, width=s * 0.05)
    star(p, c, s * 0.4, 0)


def hint(kind):
    # A small card with an arrow towards where its top goes on the physical table.
    def draw(p, c, s, f):
        if kind == "confusion":
            w, h, direction = s * 0.6, s * 0.9, (0, 1)
        else:
            w, h, direction = s * 0.9, s * 0.6, (-1, 0) if kind == "sleep" else (1, 0)
        p.rect(c - w / 2, c - h / 2, c + w / 2, c + h / 2, outline=f, width=s * 0.08, radius=s * 0.08)
        dx, dy = direction
        px, py = -dy, dx
        a = s * 0.2
        p.poly([(c + dx * a * 1.1, c + dy * a * 1.1), (c - dx * a * 0.3 + px * a, c - dy * a * 0.3 + py * a),
                (c - dx * a * 0.3 - px * a, c - dy * a * 0.3 - py * a)], f)
    return draw


def make_icons(font_path):
    icons = {
        "heart": heart, "drop": drop, "flame": flame, "crown": crown, "shield": shield, "star": star,
        "bolt": bolt, "spiral": spiral, "menu": menu, "undo": undo, "rotate": rotate, "clock": clock,
        "check": check, "sun": sun, "moon": moon, "chevron_left": chevron("left"), "chevron_right": chevron("right"),
        "triangle": triangle, "d20": d20, "coins": coins, "coin": coin_mask,
        "hint_sleep": hint("sleep"), "hint_confusion": hint("confusion"), "hint_paralysis": hint("paralysis"),
        "sleep": lambda p, c, s, f: sleep(p, c, s, f, font_path),
    }
    for name, draw in icons.items():
        pen = Pen(ICON, ICON, 0)
        draw(pen, ICON / 2, ICON * 0.88, 255)
        pen.save(os.path.join(OUT, "icons", name + ".png"), levels=False)


def make_coins():
    size = 160
    for side in ("heads", "tails"):
        pen = Pen(size, size, WHITE)
        c, r = size / 2, size / 2 - 4
        if side == "heads":
            pen.circle(c, c, r, fill=PALE, outline=BLACK, width=r / 12)
            pen.circle(c, c, r * 0.78, outline=MID, width=r / 25)
            star(pen, c, r * 0.95, BLACK)
        else:
            pen.circle(c, c, r, fill=DARK, outline=BLACK, width=r / 12)
            pen.circle(c, c, r * 0.78, outline=LIGHT, width=r / 25)
            crown(pen, c, r * 0.9, WHITE)
        pen.save(os.path.join(OUT, "art", f"coin_{side}.png"))


def make_dice():
    size = 160
    pen = Pen(size, size, WHITE)
    c = size / 2
    r = size / 2 - 4
    hexagon = [(c + r * math.cos(math.radians(a)), c + r * math.sin(math.radians(a))) for a in range(-90, 270, 60)]
    pen.poly(hexagon, BLACK)
    inner = [(c, c - r * 0.62), (c + r * 0.62, c + r * 0.42), (c - r * 0.62, c + r * 0.42)]
    pen.poly(inner, WHITE)
    for corner, target in ((0, 0), (1, 1), (2, 1), (3, 2), (4, 2), (5, 0)):
        pen.line([hexagon[corner], inner[target]], WHITE, size / 60)
    pen.save(os.path.join(OUT, "art", "d20.png"))
    pen = Pen(size, size, WHITE)
    pen.rect(8, 8, size - 8, size - 8, fill=WHITE, outline=BLACK, width=8, radius=24)
    pen.save(os.path.join(OUT, "art", "d6.png"))


def make_banner(font_path):
    w, h = 600, 294
    pen = Pen(w, h, INK)
    for i in range(0, w + h, 18):
        pen.line([(i, h), (i - h, 0)], DARK, 1)
    for angle, dx in ((-18, -70), (-6, -24), (6, 24), (18, 70)):
        card = Pen(110, 154, INK)
        card.rect(0, 0, 110, 154, fill=WHITE, outline=BLACK, width=3, radius=10)
        card.rect(8, 8, 102, 146, outline=MID, width=1.5, radius=6)
        card.poly([(55, 40), (80, 77), (55, 114), (30, 77)], PALE)
        rotated = card.image.rotate(-angle, resample=Image.BICUBIC, expand=True, fillcolor=INK)
        mask = Image.new("L", card.image.size, 255).rotate(-angle, resample=Image.BICUBIC, expand=True, fillcolor=0)
        px = pen.s(300 + dx) - rotated.width // 2
        py = pen.s(110 + abs(dx) * 0.25) - rotated.height // 2
        pen.image.paste(rotated, (px, py), mask)
    r = 37
    hexagon = [(446 + r * math.cos(math.radians(a)), 176 + r * math.sin(math.radians(a))) for a in range(-90, 270, 60)]
    pen.poly(hexagon, BLACK)
    pen.poly([(446, 176 - r * 0.62), (446 + r * 0.62, 176 + r * 0.42), (446 - r * 0.62, 176 + r * 0.42)], WHITE)
    pen.text(446, 180, "20", ImageFont.truetype(font_path, pen.s(14)), BLACK)
    pen.circle(150, 186, 30, fill=WHITE)
    pen.circle(150, 186, 27, fill=PALE, outline=BLACK, width=2.5)
    star(pen, 150, 25, BLACK, 150, 186)
    pen.save(os.path.join(OUT, "art", "banner.png"))


def make_header():
    w, h = 600, 132
    pen = Pen(w, h, INK)
    for i in range(0, w + h, 18):
        pen.line([(i, h), (i - h, 0)], DARK, 1)
    pen.rect(0, h - 6, w, h, fill=BLACK)
    pen.save(os.path.join(OUT, "art", "header.png"))


def make_screensaver(font_path):
    # Laid out in 600x800 units and saved at twice that (1200x1600), so larger screens get a sharp
    # image and 600x800 gets a clean halving. No game logos: the cover is the plugin's own art.
    w, h, k = 600, 800, 2
    pen = Pen(w * k, h * k, INK)

    def u(v):
        return v * k

    for i in range(0, w + h, 18):
        pen.line([(u(i), u(h)), (u(i - h), 0)], DARK, u(1))
    serif = os.path.join(os.path.dirname(font_path), "NotoSerif-Bold.ttf")
    title = ImageFont.truetype(serif if os.path.exists(serif) else font_path, pen.s(u(66)))
    pen.text(u(300), u(128), "Matkeeper", title, WHITE)
    pen.rect(u(250), u(182), u(350), u(188), fill=MID, radius=u(3))
    # The table seen from above: four blocks, each facing its edge.
    x0, y0, x1, y1 = 64, 236, 536, 724
    pen.rect(u(x0 + 6), u(y0 + 8), u(x1 + 6), u(y1 + 8), fill=BLACK, radius=u(30))
    pen.rect(u(x0), u(y0), u(x1), u(y1), fill=BLACK, outline=WHITE, width=u(4), radius=u(30))
    gap, pad = 14, 18
    bw = (x1 - x0 - 2 * pad - gap) / 2
    bh = (y1 - y0 - 2 * pad - gap) / 2
    number = ImageFont.truetype(serif if os.path.exists(serif) else font_path, pen.s(u(84)))
    label = ImageFont.truetype(font_path, pen.s(u(15)))
    blocks = [(0, 0, "31", True), (1, 0, "40", True), (0, 1, "40", False), (1, 1, "27", False)]
    for col, row, life, flipped in blocks:
        card = Pen(round(u(bw)), round(u(bh)), BLACK)
        cw, ch = u(bw), u(bh)
        card.rect(0, 0, cw, ch, fill=WHITE, radius=u(18))
        card.rect(u(6), u(6), cw - u(6), ch - u(6), outline=PALE, width=u(1.5), radius=u(14))
        card.text(cw / 2, ch * 0.5, life, number, BLACK)
        card.rect(cw / 2 - u(34), u(16), cw / 2 + u(34), u(42), fill=INK, radius=u(13))
        card.text(cw / 2, u(29), ("P" + str(col + 2 * row + 1)), label, WHITE)
        for sx, sign in ((cw * 0.16, "-"), (cw * 0.84, "+")):
            card.line([(sx - u(9), ch * 0.5), (sx + u(9), ch * 0.5)], MID, u(3))
            if sign == "+":
                card.line([(sx, ch * 0.5 - u(9)), (sx, ch * 0.5 + u(9))], MID, u(3))
        card.rect(cw * 0.3, ch - u(40), cw * 0.7, ch - u(16), fill=PAPER, radius=u(12))
        image = card.image.rotate(180) if flipped else card.image
        pen.image.paste(image, (pen.s(u(x0 + pad + col * (bw + gap))), pen.s(u(y0 + pad + row * (bh + gap)))))
    # The round button at the junction, with a d20.
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    pen.circle(u(cx), u(cy), u(48), fill=BLACK)
    pen.circle(u(cx), u(cy), u(42), fill=WHITE, outline=BLACK, width=u(3))
    r = 28
    hexagon = [(u(cx + r * math.cos(math.radians(a))), u(cy + r * math.sin(math.radians(a)))) for a in range(-90, 270, 60)]
    pen.poly(hexagon, BLACK)
    inner = [(u(cx), u(cy - r * 0.62)), (u(cx + r * 0.62), u(cy + r * 0.42)), (u(cx - r * 0.62), u(cy + r * 0.42))]
    pen.poly(inner, WHITE)
    pen.text(u(cx), u(cy + 3), "20", ImageFont.truetype(font_path, pen.s(u(11))), BLACK)
    pen.save(os.path.join(OUT, "screensaver.png"))


LOGO_LEVELS = {"magic": (40, 235), "pokemon": (90, 215)}
LOGO_SIZES = {"large": (220, 150), "small": (112, 60)}


def make_logos():
    for game, (black, white) in LOGO_LEVELS.items():
        source = Image.open(os.path.join(LOGO_SOURCES, game + ".png")).convert("RGBA")
        source = source.crop(source.getchannel("A").getbbox())
        flat = Image.alpha_composite(Image.new("RGBA", source.size, (255, 255, 255, 255)), source).convert("RGB")
        for name, box in LOGO_SIZES.items():
            scale = min(box[0] / flat.width, box[1] / flat.height)
            image = flat.resize((round(flat.width * scale), round(flat.height * scale)), Image.LANCZOS)
            gray = ImageOps.grayscale(image)
            gray = gray.point(lambda v: min(255, max(0, round((v - black) * 255 / (white - black)))))
            gray = gray.point(lambda v: round(v / 17) * 17)
            os.makedirs(os.path.join(OUT, "logos"), exist_ok=True)
            gray.save(os.path.join(OUT, "logos", f"{game}_{name}.png"), optimize=True)


def main():
    font_path = os.environ.get("BOLD_FONT", "/System/Library/Fonts/Supplemental/Arial Bold.ttf")
    make_icons(font_path)
    make_coins()
    make_dice()
    make_banner(font_path)
    make_header()
    make_screensaver(font_path)
    if LOGO_SOURCES:
        make_logos()
    for root, _, files in os.walk(OUT):
        for name in sorted(files):
            if name.endswith(".png"):
                path = os.path.join(root, name)
                print(f"{os.path.relpath(path, OUT)}: {os.path.getsize(path)} bytes")


if __name__ == "__main__":
    main()
