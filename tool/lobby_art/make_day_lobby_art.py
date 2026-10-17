#!/usr/bin/env python3
"""Render the lobby's Day garden and the mossy ledge under the hero tiles.

The Day look (redesign 1.1.0) is the same garden as the night lobby
(tool/assets/make_lobby_art.py, owned by the art pipeline) in daylight:
sun through the leaves, warm gold highlights, small cream flowers, a mossy
stone path at the bottom and soft depth of field, with a calm, readable
centre. Like the night art it is drawn procedurally with Pillow (no numpy,
no licensed art) and written as WebP layers the app stacks at runtime:

  assets/lobby/day/day_base.webp                 opaque sunlit garden (cover fit)
  assets/lobby/day/day_path.webp                 mossy stone path, bottom-anchored
  assets/lobby/day/day_foliage_{tl,tr,bl,br}.webp    sunlit corner foliage + flowers
  assets/lobby/day/day_ledge.webp                mossy ledge under the hero tiles (Day)
  assets/lobby/night_ledge.webp                  the same ledge after dark (Night)

Lighting that must stay tunable (sun glow, calm centre, vignette) and the
floating pollen are drawn by Flutter on top (LobbyTheme.day in
lib/app/theme.dart). Day has no lanterns and no fireflies.

Usage: python3 -I tool/lobby_art/make_day_lobby_art.py [--review DIR]
--review writes day/night composites approximating a 411x914 phone to DIR.
"""

import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/lobby"
SS = 2  # supersampling for crisp leaf and stone edges

# ---------------------------------------------------------------- helpers


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(v)))


def mix(a, b, t):
    return tuple(clamp(x + (y - x) * t) for x, y in zip(a, b))


def scale(c, k):
    return tuple(clamp(x * k) for x in c)


def vertical_gradient(w, h, stops):
    """stops: [(t, (r, g, b)), ...] with t in 0..1."""
    col = Image.new("RGB", (1, h))
    px = col.load()
    for y in range(h):
        t = y / (h - 1)
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                px[0, y] = mix(c0, c1, (t - t0) / (t1 - t0 or 1))
                break
    return col.resize((w, h), Image.BILINEAR)


def composite_at(canvas, layer, x, y):
    """alpha_composite with clipping (negative offsets allowed)."""
    x, y = int(round(x)), int(round(y))
    cw, ch = canvas.size
    lw, lh = layer.size
    sx0, sy0 = max(0, -x), max(0, -y)
    dx0, dy0 = max(0, x), max(0, y)
    w, h = min(lw - sx0, cw - dx0), min(lh - sy0, ch - dy0)
    if w <= 0 or h <= 0:
        return
    canvas.alpha_composite(layer, (dx0, dy0), (sx0, sy0, sx0 + w, sy0 + h))


def radial_mask(w, h, power=1.0):
    """L mask, 255 at the centre fading to 0 at the ellipse edge."""
    g = Image.radial_gradient("L").point(lambda v: min(255, v * 255 // 181))
    g = ImageChops.invert(g.resize((max(2, w), max(2, h)), Image.BILINEAR))
    if power != 1.0:
        g = g.point(lambda v: clamp(255 * (v / 255) ** power))
    return g


def glow_layer(r, color, alpha=255, power=1.6, squash=1.0):
    w, h = max(2, int(r * 2)), max(2, int(r * 2 * squash))
    m = radial_mask(w, h, power).point(lambda v: v * alpha // 255)
    layer = Image.new("RGBA", (w, h), color + (0,))
    layer.putalpha(m)
    return layer


def screen_light(rgb, mask, color):
    """Screen-blends `color` into an RGB image, weighted by an L mask."""
    light = Image.merge("RGB", [mask.point(lambda v, c=c: v * c // 255) for c in color])
    return ImageChops.screen(rgb, light)


def placed_mask(size, mask, cx, cy):
    out = Image.new("L", size, 0)
    out.paste(mask, (int(cx - mask.width / 2), int(cy - mask.height / 2)))
    return out


def leaf_points(cx, cy, length, width, angle, steps=36, tip=0.85):
    a = math.radians(angle)
    pts = []
    for i in range(steps + 1):
        t = -1 + 2 * i / steps
        pts.append((t * length / 2, (1 - t * t) ** tip * width / 2 * (1 - 0.18 * t)))
    for i in range(steps + 1):
        t = 1 - 2 * i / steps
        pts.append((t * length / 2, -((1 - t * t) ** tip) * width / 2 * (1 - 0.18 * t)))
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def leaf_layer(length, width, angle, base, *, light=1.7, dark=0.42, blur=0.0, veins=True, sheen=0.55,
               highlight=(255, 255, 236), light_from=(0.3, 0.25), tip=0.85, rim=None):
    """A glossy leaf on its own small canvas; returns (layer, (x0, y0)).

    rim: optional (color, alpha) of a warm sunlit edge on the lit side.
    """
    pts = leaf_points(0, 0, length, width, angle, tip=tip)
    pad = int(blur * 3 + 6)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, y0 = int(min(xs)) - pad, int(min(ys)) - pad
    w, h = int(max(xs) - x0) + pad + 1, int(max(ys) - y0) + pad + 1
    local = [(x - x0, y - y0) for x, y in pts]
    size = (w, h)
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(local, fill=255)
    bx0, by0, bx1, by1 = mask.getbbox()
    bw, bh = bx1 - bx0, by1 - by0
    grad = Image.radial_gradient("L").resize((max(2, int(bw * 1.9)), max(2, int(bh * 1.9))))
    shade = Image.new("L", size, 255)
    shade.paste(grad, (int(bx0 + bw * light_from[0] - grad.width / 2), int(by0 + bh * light_from[1] - grad.height / 2)))
    shade = ImageChops.invert(shade)
    lit = scale(base, light)
    deep = scale(base, dark)
    layer = Image.composite(Image.new("RGB", size, lit), Image.new("RGB", size, deep), shade).convert("RGBA")
    a = math.radians(angle)
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    cx, cy = -x0, -y0
    if veins:
        d = ImageDraw.Draw(layer)
        rib = scale(base, 1.5)
        d.line((cx - ux * length * 0.48, cy - uy * length * 0.48, cx + ux * length * 0.45, cy + uy * length * 0.45),
               fill=rib + (200,), width=max(1, int(width * 0.03)))
        for k in (-0.32, -0.14, 0.04, 0.22):
            px, py = cx + ux * length * k, cy + uy * length * k
            for side in (1, -1):
                ex = px + (ux * 0.5 + nx * side * 0.85) * width * 0.42
                ey = py + (uy * 0.5 + ny * side * 0.85) * width * 0.42
                d.line((px, py, ex, ey), fill=rib + (60,), width=max(1, int(width * 0.014)))
    if sheen:
        sm = Image.new("L", size, 0)
        ImageDraw.Draw(sm).polygon(
            [(x - x0, y - y0) for x, y in leaf_points(nx * width * 0.14, ny * width * 0.14, length * 0.68, width * 0.3, angle)],
            fill=int(255 * sheen))
        sm = sm.filter(ImageFilter.GaussianBlur(width * 0.07 + 1))
        layer = Image.composite(Image.new("RGBA", size, highlight + (255,)), layer, ImageChops.multiply(sm, mask))
    if rim:
        color, alpha = rim
        # Sunlight catching the upper edge: the mask minus itself shifted
        # away from the light.
        shifted = ImageChops.offset(mask, int(width * 0.06) + 1, int(width * 0.08) + 1)
        edge = ImageChops.subtract(mask, shifted).filter(ImageFilter.GaussianBlur(width * 0.02 + 0.6))
        layer = Image.composite(Image.new("RGBA", size, color + (255,)), layer, edge.point(lambda v: v * alpha // 255))
    layer.putalpha(mask)
    if blur:
        layer = layer.convert("RGBa").filter(ImageFilter.GaussianBlur(blur)).convert("RGBA")
    return layer, (x0, y0)


def draw_leaf(canvas, cx, cy, length, width, angle, base, **kw):
    layer, (x0, y0) = leaf_layer(length, width, angle, base, **kw)
    composite_at(canvas, layer, cx + x0, cy + y0)


def petal_points(cx, cy, length, width, angle, steps=28):
    a = math.radians(angle)
    pts = []
    for i in range(steps * 2):
        t = 2 * math.pi * i / (steps * 2)
        x = (math.cos(t) + 1) / 2 * length
        y = math.sin(t) * width / 2 * (0.35 + 0.65 * math.sin(min(math.pi, x / length * math.pi * 0.95 + 0.15)))
        pts.append((x, y))
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def flower_layer(r, *, petals=5, rot=0.0, tint=(255, 252, 242), shade=(226, 214, 184), centre=(240, 186, 58),
                 blur=0.0, light=1.0):
    """A cream five-petal flower (jasmine / plumeria) on its own canvas."""
    pad = int(blur * 3 + 4)
    size = int(r * 2 + pad * 2)
    c = size / 2
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for k in range(petals):
        ang = rot + k * 360 / petals
        pts = petal_points(c, c, r, r * 0.78, ang)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).polygon(pts, fill=255)
        g = radial_mask(int(r * 2.2), int(r * 2.2), 0.8)
        sh = Image.new("L", (size, size), 0)
        a = math.radians(ang)
        sh.paste(g, (int(c + math.cos(a) * r * 0.62 - g.width / 2), int(c + math.sin(a) * r * 0.62 - g.height / 2 - r * 0.1)))
        fill = Image.composite(Image.new("RGB", (size, size), scale(tint, light)),
                               Image.new("RGB", (size, size), scale(shade, light)), sh).convert("RGBA")
        fill.putalpha(mask)
        edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(edge).line(pts + [pts[0]], fill=scale(shade, 0.8 * light) + (110,), width=max(1, int(r * 0.03)))
        layer.alpha_composite(fill)
        layer.alpha_composite(edge)
    d = ImageDraw.Draw(layer)
    cr = r * 0.2
    d.ellipse((c - cr, c - cr, c + cr, c + cr), fill=scale(centre, light) + (255,))
    hi = scale(mix(centre, (255, 244, 190), 0.6), light)
    d.ellipse((c - cr * 0.55, c - cr * 0.65, c + cr * 0.25, c + cr * 0.1), fill=hi + (255,))
    for k in range(7):
        a = math.radians(k * 360 / 7 + rot)
        px, py = c + math.cos(a) * cr * 1.35, c + math.sin(a) * cr * 1.35
        d.ellipse((px - r * 0.035, py - r * 0.035, px + r * 0.035, py + r * 0.035), fill=scale((200, 136, 40), light) + (255,))
    if blur:
        layer = layer.convert("RGBa").filter(ImageFilter.GaussianBlur(blur)).convert("RGBA")
    return layer


def draw_flower(canvas, cx, cy, r, **kw):
    f = flower_layer(r, **kw)
    composite_at(canvas, f, cx - f.width / 2, cy - f.height / 2)


def bud(canvas, cx, cy, r, angle, light=1.0):
    """A closed cream bud on a short stem."""
    pts = leaf_points(cx, cy, r * 2.2, r * 1.1, angle, tip=0.6)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(pts, fill=scale((250, 240, 214), light) + (255,))
    canvas.alpha_composite(layer)


def disc(r, color, alpha, rim=1.0, blur_frac=0.08):
    pad = int(r * 0.4 + 4)
    size = int(r * 2 + pad * 2)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c = size / 2
    d.ellipse((c - r, c - r, c + r, c + r), fill=color + (clamp(alpha),))
    if rim != 1.0:
        d.ellipse((c - r, c - r, c + r, c + r), outline=color + (clamp(alpha * rim),), width=max(1, int(r * 0.08)))
    return layer.filter(ImageFilter.GaussianBlur(max(0.6, r * blur_frac)))


def bokeh(canvas, rnd, count, box, rmin, rmax, colors, amin, amax, blur_frac=0.08, weight=None):
    x0, y0, x1, y1 = box
    for _ in range(count):
        x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        if weight and rnd.random() > weight(x, y):
            continue
        r = rnd.uniform(rmin, rmax)
        layer = disc(r, rnd.choice(colors), rnd.uniform(amin, amax), blur_frac=blur_frac)
        composite_at(canvas, layer, x - layer.width / 2, y - layer.height / 2)


def blob_mass(canvas, rnd, count, box, lmin, lmax, colors, blur, alpha=255, angle=(0, 360)):
    """Out-of-focus foliage: flat leaf silhouettes blurred together."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    for _ in range(count):
        length = rnd.uniform(lmin, lmax)
        pts = leaf_points(rnd.uniform(x0, x1), rnd.uniform(y0, y1), length, length * rnd.uniform(0.45, 0.6),
                          rnd.uniform(*angle))
        m = Image.new("L", canvas.size, 0)
        ImageDraw.Draw(m).polygon(pts, fill=alpha)
        layer.paste(Image.new("RGBA", canvas.size, rnd.choice(colors) + (255,)), (0, 0), m)
    canvas.alpha_composite(layer.convert("RGBa").filter(ImageFilter.GaussianBlur(blur)).convert("RGBA"))


def fade_alpha(img, top_len=0.0, bottom_len=0.0, left_len=0.0, right_len=0.0):
    """Multiplies alpha by smooth ramps at the edges (fractions of size)."""
    w, h = img.size
    col = Image.new("L", (1, h), 255)
    row = Image.new("L", (w, 1), 255)

    def smooth(f):
        f = max(0.0, min(1.0, f))
        return int(255 * f * f * (3 - 2 * f))

    for y in range(h):
        ty = y / h
        f = 1.0
        if top_len and ty < top_len:
            f *= ty / top_len
        if bottom_len and ty > 1 - bottom_len:
            f *= (1 - ty) / bottom_len
        col.putpixel((0, y), smooth(f))
    for x in range(w):
        tx = x / w
        f = 1.0
        if left_len and tx < left_len:
            f *= tx / left_len
        if right_len and tx > 1 - right_len:
            f *= (1 - tx) / right_len
        row.putpixel((x, 0), smooth(f))
    ramp = ImageChops.multiply(col.resize((w, h)), row.resize((w, h)))
    img.putalpha(ImageChops.multiply(img.getchannel("A"), ramp))
    return img


def save(img, rel, quality=84):
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    if img.mode == "RGBA" and img.getchannel("A").getextrema() == (255, 255):
        img = img.convert("RGB")
    img.save(path, "WEBP", quality=quality, method=6, alpha_quality=90)
    print(f"{path.relative_to(ROOT)}  {img.size}  {path.stat().st_size // 1024} KB")
    return img


# ---------------------------------------------------------------- palette

# Sunlit leaf greens (fresh, slightly yellow), and the deeper shade greens.
SUN_GREENS = [(78, 150, 62), (96, 166, 70), (62, 134, 58), (118, 178, 74), (54, 120, 54)]
SHADE_GREENS = [(38, 100, 56), (46, 112, 60), (30, 88, 50), (56, 124, 64)]
NIGHT_GREENS = [(22, 86, 60), (28, 100, 68), (16, 72, 52), (34, 112, 74), (14, 62, 48)]
WARM_HIGHLIGHT = (255, 250, 214)
SUN_RIM = (255, 236, 160)

# ---------------------------------------------------------------- base

W, H = 1080, 2340


def day_base():
    rnd = random.Random(1101)
    # Sky glimpsed through the canopy at the top, garden green in the middle,
    # mossy shade toward the bottom (under the path).
    img = vertical_gradient(W, H, [
        (0.0, (242, 240, 192)),
        (0.1, (214, 226, 150)),
        (0.24, (156, 194, 104)),
        (0.4, (104, 160, 86)),
        (0.58, (72, 134, 72)),
        (0.8, (56, 116, 62)),
        (1.0, (42, 96, 52)),
    ]).convert("RGBA")
    # Far trunks, hazy with distance and sunlight.
    trunks = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    td = ImageDraw.Draw(trunks)
    for x, w_, col, a in [(90, 86, (70, 92, 62), 150), (300, 40, (98, 122, 80), 120), (W - 140, 96, (66, 88, 58), 150),
                          (W - 330, 44, (98, 122, 80), 110), (560, 26, (124, 148, 98), 90), (790, 30, (118, 142, 94), 90)]:
        td.polygon([(x - w_ / 2, 0), (x + w_ / 2, 0), (x + w_ * 0.75, H * 0.78), (x - w_ * 0.75, H * 0.78)], fill=col + (a,))
    img.alpha_composite(trunks.filter(ImageFilter.GaussianBlur(16)))
    # Sunlit canopy, far out of focus, at the top.
    blob_mass(img, rnd, 40, (-120, -120, W + 120, 760), 240, 460,
              [(150, 192, 98), (172, 206, 112), (128, 178, 88), (196, 218, 132)], 34)
    # Shaded foliage masses down both sides (darker, a little sharper: nearer).
    blob_mass(img, rnd, 44, (-170, 380, 270, 2000), 240, 470, [scale(c, 1.15) for c in SHADE_GREENS], 26)
    blob_mass(img, rnd, 44, (W - 270, 380, W + 170, 2000), 240, 470, [scale(c, 1.15) for c in SHADE_GREENS], 26)
    # A low hedge behind the middle of the screen (calm, even, readable).
    blob_mass(img, rnd, 36, (60, 1150, W - 60, 1750), 220, 380, [(36, 98, 58), (42, 108, 62), (32, 90, 54)], 30)
    rgb = img.convert("RGB")
    # The sun: high on the right, washing the canopy and falling as shafts.
    sun = placed_mask((W, H), radial_mask(int(W * 2.1), int(H * 1.0), 1.3), W * 0.7, H * 0.0)
    rgb = screen_light(rgb, sun.point(lambda v: v * 215 // 255), (255, 240, 190))
    shafts = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(shafts)
    sx, sy = W * 0.86, -H * 0.06
    for ang, spread, a in [(108, 2.4, 70), (116, 1.6, 55), (124, 3.0, 64), (133, 1.8, 46), (141, 2.6, 52),
                           (101, 1.4, 40), (149, 1.5, 34)]:
        a0, a1 = math.radians(ang - spread), math.radians(ang + spread)
        far = H * 1.15
        sd.polygon([(sx, sy), (sx + math.cos(a0) * far, sy + math.sin(a0) * far),
                    (sx + math.cos(a1) * far, sy + math.sin(a1) * far)], fill=a)
    shafts = shafts.filter(ImageFilter.GaussianBlur(26))
    # Rays fade out toward the bottom (they meet the hedge and the path).
    fade = vertical_gradient(W, H, [(0, (255,) * 3), (0.35, (220,) * 3), (0.72, (60,) * 3), (1, (0,) * 3)]).convert("L")
    rgb = screen_light(rgb, ImageChops.multiply(shafts, fade), (255, 236, 176))
    img = rgb.convert("RGBA")
    # Nearer, sun-dappled leaves framing both sides (less blur: closer).
    near = [(70, 138, 66), (92, 158, 74), (58, 124, 60), (112, 172, 80)]
    blob_mass(img, rnd, 30, (-200, 300, 170, 2100), 200, 380, near, 16)
    blob_mass(img, rnd, 30, (W - 170, 300, W + 200, 2100), 200, 380, near, 16)
    # Sparkle of sunlight through leaves: soft warm discs, most near the top.
    top = lambda x, y: max(0.04, 1 - y / (H * 0.55)) ** 1.5
    bokeh(img, rnd, 80, (0, 0, W, H * 0.62), 8, 34, [(255, 250, 222), (255, 238, 176), (236, 244, 190)], 20, 80,
          weight=top, blur_frac=0.3)
    side = lambda x, y: (abs(x - W / 2) / (W / 2)) ** 1.6
    bokeh(img, rnd, 70, (0, 500, W, 1900), 5, 16, [(255, 236, 160), (250, 248, 220)], 50, 150, weight=side, blur_frac=0.2)
    # A few distant cream blossoms, out of focus, at the sides.
    for _ in range(16):
        x = rnd.choice((rnd.uniform(-20, W * 0.2), rnd.uniform(W * 0.8, W + 20)))
        y = rnd.uniform(H * 0.18, H * 0.75)
        f = flower_layer(rnd.uniform(16, 30), rot=rnd.uniform(0, 72), blur=rnd.uniform(5, 9), light=0.96)
        composite_at(img, f, x - f.width / 2, y - f.height / 2)
    # Calm centre: a soft, slightly deeper green oval behind the title and
    # buttons, so ivory and gold read on the bright scene.
    calm = glow_layer(W * 0.6, (22, 76, 46), 100, power=1.15, squash=1.55)
    composite_at(img, calm, W * 0.5 - calm.width / 2, H * 0.56 - calm.height / 2)
    return img.convert("RGB")


# ---------------------------------------------------------------- path

PW, PH = 1080, 640


def stone_mask(poly, size, round_px):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    m = m.filter(ImageFilter.GaussianBlur(round_px))
    return m.point(lambda v: 255 if v > 150 else 0).filter(ImageFilter.GaussianBlur(1.0))


def mottle(size, rnd, count, rmin, rmax, blur):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    w, h = size
    for _ in range(count):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        r = rnd.uniform(rmin, rmax)
        d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=rnd.randint(60, 200))
    return m.filter(ImageFilter.GaussianBlur(blur))


def day_path():
    """Perspective flagstone path in dappled sunlight, mossy joints, daisies
    along both edges, fading upward into the garden."""
    rnd = random.Random(1303)
    w, h = PW * SS, PH * SS
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    z_far, z_near = 9.0, 1.35

    def y_of(z):
        return (1 / z - 1 / z_far) / (1 / z_near - 1 / z_far) * h * 1.06 + h * 0.04

    def x_of(u, z):
        k = (1 / z - 1 / z_far) / (1 / z_near - 1 / z_far)
        return w / 2 + u * (0.2 + 0.62 * k) * w

    ground = vertical_gradient(w, h, [(0, (58, 104, 56)), (1, (40, 78, 42))]).convert("RGBA")
    gm = Image.new("L", (w, h), 0)
    ImageDraw.Draw(gm).polygon([(x_of(-1.35, z_far), y_of(z_far)), (x_of(1.35, z_far), y_of(z_far)),
                                (x_of(1.5, 1.0), h * 1.3), (x_of(-1.5, 1.0), h * 1.3)], fill=255)
    ground.putalpha(gm.filter(ImageFilter.GaussianBlur(40 * SS)))
    canvas.alpha_composite(ground)

    rows = 15
    zs = [z_far - (z_far - z_near) * (j / rows) ** 0.75 for j in range(rows + 1)]
    phase = [rnd.uniform(0, 6.3) for _ in zs]

    def row_z(j, u):
        dz = (zs[max(0, j - 1)] - zs[min(rows, j + 1)]) * 0.06
        return zs[j] + dz * math.sin(u * 3.1 + phase[j]) + dz * 0.5 * math.sin(u * 7.3 + phase[j] * 2)

    base = (136, 132, 110)
    moss_col = (90, 146, 60)
    for j in range(rows):
        n = rnd.randint(7, 11)
        cuts = sorted([-1.3] + [rnd.uniform(-1.05, 1.05) for _ in range(n - 1)] + [1.3])
        for i in range(len(cuts) - 1):
            u0, u1 = cuts[i], cuts[i + 1]
            slant0, slant1 = rnd.uniform(-0.06, 0.06), rnd.uniform(-0.06, 0.06)
            us = [u0 + (u1 - u0) * k / 5 for k in range(6)]
            poly = [(x_of(u, row_z(j, u)), y_of(row_z(j, u))) for u in us]
            poly += [(x_of(u + (slant1 if u == u1 else slant0), row_z(j + 1, u)), y_of(row_z(j + 1, u))) for u in reversed(us)]
            cxp = sum(p[0] for p in poly) / len(poly)
            cyp = sum(p[1] for p in poly) / len(poly)
            row_h = y_of(zs[j + 1]) - y_of(zs[j])
            gap = 0.88
            poly = [(cxp + (x - cxp) * gap, cyp + (y - cyp) * gap) for x, y in poly]
            xs, ys = [p[0] for p in poly], [p[1] for p in poly]
            bx0, by0 = int(min(xs)) - 24, int(min(ys)) - 24
            bw, bh = int(max(xs)) - bx0 + 24, int(max(ys)) - by0 + 24
            if bx0 > w or bx0 + bw < 0:
                continue
            local = [(x - bx0, y - by0) for x, y in poly]
            m = stone_mask(local, (bw, bh), max(3, row_h * 0.22))
            tone = scale(mix(base, (168, 156, 126), rnd.uniform(0, 0.7)), rnd.uniform(0.86, 1.08))
            g = vertical_gradient(bw, bh, [(0, scale(tone, 1.18)), (0.35, tone), (1, scale(tone, 0.68))]).convert("RGBA")
            mt = mottle((bw, bh), rnd, 8, bw * 0.08, bw * 0.22, bw * 0.06 + 2)
            g = Image.composite(Image.new("RGBA", (bw, bh), scale(tone, 0.82) + (255,)), g, mt.point(lambda v: v // 2))
            tex = Image.new("L", (bw, bh), 0)
            td = ImageDraw.Draw(tex)
            for _ in range(int(bw * bh / 900)):
                x, y = rnd.uniform(0, bw), rnd.uniform(0, bh)
                rr = rnd.uniform(0.8, 2.0) * SS
                td.ellipse((x - rr, y - rr, x + rr, y + rr), fill=rnd.randint(20, 56))
            g = Image.composite(Image.new("RGBA", (bw, bh), scale(tone, 0.6) + (255,)), g, tex.filter(ImageFilter.GaussianBlur(0.8)))
            moss = Image.new("L", (bw, bh), 0)
            md = ImageDraw.Draw(moss)
            for _ in range(rnd.randint(6, 12)):
                edge = rnd.random()
                x = rnd.uniform(0, bw) if edge < 0.6 else rnd.choice((rnd.uniform(0, bw * 0.15), rnd.uniform(bw * 0.85, bw)))
                y = rnd.choice((rnd.uniform(0, bh * 0.25), rnd.uniform(bh * 0.75, bh))) if edge < 0.6 else rnd.uniform(0, bh)
                rr = rnd.uniform(0.05, 0.17) * bw
                md.ellipse((x - rr, y - rr * 0.5, x + rr, y + rr * 0.5), fill=rnd.randint(150, 235))
            moss = moss.filter(ImageFilter.GaussianBlur(3 * SS))
            mcol = vertical_gradient(bw, bh, [(0, scale(moss_col, 1.25)), (1, scale(moss_col, 0.82))]).convert("RGBA")
            g = Image.composite(mcol, g, moss)
            rim = Image.new("L", (bw, bh), 0)
            ImageDraw.Draw(rim).line(local[:6], fill=110, width=max(2, int(row_h * 0.06)))
            rim = ImageChops.multiply(rim.filter(ImageFilter.GaussianBlur(row_h * 0.04 + 1)), m)
            g = Image.composite(Image.new("RGBA", (bw, bh), (250, 244, 214, 255)), g, rim)
            g.putalpha(m)
            sh = Image.new("RGBA", (bw, bh), (12, 30, 14, 0))
            sh.putalpha(m.point(lambda v: v * 110 // 255))
            composite_at(canvas, sh.filter(ImageFilter.GaussianBlur(4 * SS)), bx0 + 2 * SS, by0 + 4 * SS)
            composite_at(canvas, g, bx0, by0)
    # Grass, small leaves and daisies along both edges.
    for side in (-1, 1):
        for _ in range(26):
            t = rnd.uniform(0.0, 1.0)
            z = z_far - (z_far - z_near) * t
            x = x_of(side * rnd.uniform(1.0, 1.35), z)
            y = y_of(z)
            ln = (24 + 120 * t) * SS / 2
            draw_leaf(canvas, x, y - ln * 0.3, ln, ln * 0.42, -90 + side * rnd.uniform(10, 65) + rnd.uniform(-20, 20),
                      rnd.choice(SUN_GREENS), veins=t > 0.5, sheen=0.35, highlight=WARM_HIGHLIGHT,
                      blur=(1 - t) * 3 * SS)
        for _ in range(9):
            t = rnd.uniform(0.15, 1.0)
            z = z_far - (z_far - z_near) * t
            x = x_of(side * rnd.uniform(1.02, 1.3), z)
            y = y_of(z) - rnd.uniform(0, 30) * SS
            draw_flower(canvas, x, y, (10 + 34 * t) * SS / 2 * 1.4, rot=rnd.uniform(0, 72), blur=(1 - t) * 2.5 * SS)
    img = canvas.resize((PW, PH), Image.LANCZOS)
    rgb, a = img.convert("RGB"), img.getchannel("A")
    # Dappled sunlight on the stones (and leaf shade between the pools).
    light = Image.new("L", (PW, PH), 0)
    ld = ImageDraw.Draw(light)
    for _ in range(20):
        x, y = rnd.uniform(0, PW), rnd.uniform(PH * 0.1, PH)
        rx = rnd.uniform(40, 140) * (0.5 + y / PH)
        ld.ellipse((x - rx, y - rx * 0.36, x + rx, y + rx * 0.36), fill=rnd.randint(60, 130))
    light = light.filter(ImageFilter.GaussianBlur(18))
    rgb = screen_light(rgb, light, (255, 234, 170))
    shade = vertical_gradient(PW, PH, [(0, (255,) * 3), (0.6, (240,) * 3), (1, (176,) * 3)])
    rgb = ImageChops.multiply(rgb, shade)
    img = rgb.convert("RGBA")
    img.putalpha(a)
    soft = img.filter(ImageFilter.GaussianBlur(3))
    fm = vertical_gradient(PW, PH, [(0, (255,) * 3), (0.3, (0,) * 3), (0.85, (0,) * 3), (1, (180,) * 3)]).convert("L")
    img = Image.composite(soft, img, fm)
    return fade_alpha(img, top_len=0.3)


# ---------------------------------------------------------------- foliage


def foliage(w, h, origin, direction, seed, *, leaves=30, flowers=(), buds=(), spread=62, reach_k=1.0, size_k=1.0,
            back_blur=8, front_blur=0.0, broad=False, greens=SUN_GREENS, back=SHADE_GREENS, light=1.0):
    """Sunlit leaves fanning from `origin` toward `direction` (degrees), with
    flowers: (angle offset, distance fraction, radius fraction, blur)."""
    rnd = random.Random(seed)
    canvas = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    ox, oy = origin[0] * SS, origin[1] * SS
    reach = max(w, h) * SS * reach_k
    layers = [(leaves // 2, back_blur * SS, back, 1.2), (leaves - leaves // 2, front_blur * SS, greens, 1.0)]
    for li, (count, blur, cols, sk) in enumerate(layers):
        for _ in range(count):
            ang = direction + rnd.uniform(-spread, spread)
            dist = rnd.uniform(0.02, 0.55) * reach * (0.8 if li else 1)
            cx = ox + math.cos(math.radians(ang)) * dist
            cy = oy + math.sin(math.radians(ang)) * dist
            length = rnd.uniform(0.2, 0.36) * reach * sk * size_k * (1 - dist / reach * 0.55)
            width = length * (rnd.uniform(0.5, 0.62) if broad else rnd.uniform(0.38, 0.48))
            base = scale(rnd.choice(cols), light * (0.85 if li == 0 else 1))
            draw_leaf(canvas, cx, cy, length, width, ang + rnd.uniform(-30, 30), base, blur=blur, sheen=0.32,
                      highlight=WARM_HIGHLIGHT, light=1.38, dark=0.42,
                      rim=(SUN_RIM, 190) if li and light >= 1 else None)
    for ang_off, dist_f, r_f, blur in flowers:
        ang = direction + ang_off
        dist = dist_f * reach
        fl = flower_layer(r_f * reach, rot=rnd.uniform(0, 72), blur=blur * SS, light=light)
        composite_at(canvas, fl, ox + math.cos(math.radians(ang)) * dist - fl.width / 2,
                     oy + math.sin(math.radians(ang)) * dist - fl.height / 2)
    for ang_off, dist_f, r_f in buds:
        ang = direction + ang_off
        dist = dist_f * reach
        bud(canvas, ox + math.cos(math.radians(ang)) * dist, oy + math.sin(math.radians(ang)) * dist, r_f * reach,
            rnd.uniform(0, 360), light=light)
    return canvas.resize((w, h), Image.LANCZOS)


def foliage_set():
    return {
        # Sprays from the middle of the side edges (Day only), half out of focus.
        "day_foliage_ml": foliage(520, 900, (0, 470), -8, 151, leaves=30, spread=66, back_blur=10, front_blur=1.5,
                                  reach_k=0.9, flowers=[(-24, 0.2, 0.05, 0), (16, 0.27, 0.042, 1.2), (-2, 0.33, 0.036, 2.5)]),
        "day_foliage_mr": foliage(520, 900, (520, 430), 188, 157, leaves=30, spread=66, back_blur=10, front_blur=1.5,
                                  reach_k=0.9, broad=True, flowers=[(14, 0.22, 0.046, 0.8), (-22, 0.3, 0.038, 2.0)]),
        "day_foliage_tl": foliage(760, 900, (0, 0), 52, 112, leaves=46, spread=58,
                                  flowers=[(-8, 0.27, 0.06, 0), (14, 0.4, 0.045, 0), (-30, 0.42, 0.04, 1.5),
                                           (30, 0.2, 0.05, 0), (-2, 0.52, 0.035, 2.5)],
                                  buds=[(6, 0.33, 0.012), (-18, 0.36, 0.011)]),
        "day_foliage_tr": foliage(780, 1000, (780, 0), 128, 124, leaves=48, spread=60, size_k=1.12, broad=True,
                                  flowers=[(10, 0.3, 0.05, 0), (-14, 0.4, 0.04, 1.2), (24, 0.46, 0.035, 2.5)]),
        # Flowering bushes in the bottom corners, slightly soft (nearest).
        "day_foliage_bl": foliage(640, 640, (0, 640), -48, 138, leaves=44, spread=58, back_blur=12, front_blur=2.0,
                                  reach_k=1.25,
                                  flowers=[(-6, 0.3, 0.065, 0.6), (16, 0.42, 0.052, 1.0), (-26, 0.42, 0.05, 1.6),
                                           (30, 0.22, 0.055, 0.4), (4, 0.16, 0.06, 0.8), (-40, 0.26, 0.05, 1.0),
                                           (40, 0.36, 0.045, 1.8)]),
        "day_foliage_br": foliage(660, 660, (660, 660), -128, 142, leaves=44, spread=58, back_blur=12, front_blur=2.0,
                                  reach_k=1.25,
                                  flowers=[(8, 0.3, 0.064, 0.6), (-18, 0.4, 0.05, 1.2), (26, 0.4, 0.045, 1.8),
                                           (-36, 0.24, 0.055, 0.5), (0, 0.17, 0.06, 0.8), (38, 0.26, 0.05, 1.0)]),
    }


# ---------------------------------------------------------------- hero ledge

LW, LH = 1080, 360


def ledge(night):
    """A mossy rock the hero tiles stand on, with leafy sprigs and small cream
    flowers spilling over both ends. Its lower part fades out so it melts into
    the scene behind the title."""
    rnd = random.Random(2202 if night else 2201)
    w, h = LW * SS, LH * SS
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # Silhouette: moss cushions along a gentle arc (bumpy top), over a rock
    # body with rounded ends.
    shape = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(shape)
    for i in range(22):
        t = i / 21
        x = w * (0.13 + 0.74 * t) + rnd.uniform(-0.01, 0.01) * w
        cy = h * (0.44 - 0.05 * math.sin(t * math.pi))
        rx = rnd.uniform(0.06, 0.1) * w
        ry = rnd.uniform(0.13, 0.19) * h * (0.75 + 0.25 * math.sin(t * math.pi))
        sd.ellipse((x - rx, cy - ry, x + rx, cy + ry), fill=255)
    sd.rounded_rectangle((w * 0.07, h * 0.42, w * 0.93, h * 1.2), radius=int(h * 0.3), fill=255)
    shape = shape.filter(ImageFilter.GaussianBlur(6 * SS)).point(lambda v: 255 if v > 128 else 0)
    shape = shape.filter(ImageFilter.GaussianBlur(1.0 * SS))
    if night:
        rock_hi, rock_lo, moss_hi, moss_lo, lit, lit_a = (44, 66, 56), (10, 30, 24), (40, 104, 66), (16, 60, 42), (255, 204, 120), 80
        greens, lightk, leaf_hi, flower_light = NIGHT_GREENS, 0.95, (200, 236, 220), 0.86
    else:
        rock_hi, rock_lo, moss_hi, moss_lo, lit, lit_a = (120, 132, 104), (34, 66, 42), (112, 170, 70), (48, 112, 52), (255, 238, 168), 170
        greens, lightk, leaf_hi, flower_light = SUN_GREENS, 1.0, WARM_HIGHLIGHT, 1.0
    body = vertical_gradient(w, h, [(0, rock_hi), (0.4, rock_hi), (0.62, mix(rock_hi, rock_lo, 0.65)), (1, rock_lo)]).convert("RGBA")
    # Weathered stone patches on the front face.
    patches = Image.new("L", (w, h), 0)
    pd = ImageDraw.Draw(patches)
    for _ in range(26):
        x, y = rnd.uniform(w * 0.1, w * 0.9), rnd.uniform(h * 0.46, h * 0.75)
        rx = rnd.uniform(0.03, 0.08) * w
        pd.ellipse((x - rx, y - rx * 0.3, x + rx, y + rx * 0.3), fill=rnd.randint(40, 120))
    body = Image.composite(Image.new("RGBA", (w, h), scale(rock_hi, 1.12) + (255,)), body,
                           patches.filter(ImageFilter.GaussianBlur(6 * SS)))
    # Moss over the top and spilling down the face.
    moss = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(moss)
    for _ in range(140):
        x = rnd.uniform(w * 0.06, w * 0.94)
        y = rnd.uniform(h * 0.2, h * 0.5) + (rnd.uniform(0, 0.16) * h if rnd.random() < 0.3 else 0)
        r = rnd.uniform(0.015, 0.05) * w
        md.ellipse((x - r, y - r * 0.55, x + r, y + r * 0.55), fill=rnd.randint(170, 255))
    moss = moss.filter(ImageFilter.GaussianBlur(3 * SS))
    mcol = vertical_gradient(w, h, [(0, scale(moss_hi, 1.1)), (0.32, moss_hi), (0.55, moss_lo), (1, moss_lo)]).convert("RGBA")
    body = Image.composite(mcol, body, moss)
    speck = Image.new("L", (w, h), 0)
    spd = ImageDraw.Draw(speck)
    for _ in range(4200):
        x, y = rnd.uniform(0, w), rnd.uniform(h * 0.18, h * 0.6)
        r = rnd.uniform(0.7, 2.0) * SS
        spd.ellipse((x - r, y - r, x + r, y + r), fill=rnd.randint(50, 160))
    body = Image.composite(Image.new("RGBA", (w, h), scale(moss_hi, 1.4) + (255,)), body, ImageChops.multiply(speck, moss))
    dark = Image.new("L", (w, h), 0)
    dd = ImageDraw.Draw(dark)
    for _ in range(1800):
        x, y = rnd.uniform(0, w), rnd.uniform(h * 0.2, h * 0.7)
        r = rnd.uniform(0.7, 2.2) * SS
        dd.ellipse((x - r, y - r, x + r, y + r), fill=rnd.randint(40, 120))
    body = Image.composite(Image.new("RGBA", (w, h), scale(moss_lo, 0.6) + (255,)), body, dark)
    # Light catching the top edge (sun by day, lantern-warm by night).
    edge = ImageChops.subtract(shape, ImageChops.offset(shape, 0, int(12 * SS)))
    edge = edge.filter(ImageFilter.GaussianBlur(4 * SS))
    body = Image.composite(Image.new("RGBA", (w, h), lit + (255,)), body, edge.point(lambda v: v * lit_a // 255))
    body.putalpha(shape)
    shadow = Image.new("RGBA", (w, h), (4, 20, 12, 0))
    shadow.putalpha(shape.point(lambda v: v * 110 // 255).filter(ImageFilter.GaussianBlur(16 * SS)))
    canvas.alpha_composite(shadow, (0, int(10 * SS)))
    canvas.alpha_composite(body)
    # Leafy sprigs at both ends, reaching out, up and drooping over the ends.
    for side in (-1, 1):
        ox = w * (0.5 + side * 0.39)
        oy = h * 0.4
        for k in range(22):
            if k % 4 == 0:
                ang = 90 + side * rnd.uniform(-50, -15) if side > 0 else 90 + rnd.uniform(15, 50)
            elif k % 4 == 1:
                ang = (0 if side > 0 else 180) + rnd.uniform(-25, 25)
            else:
                ang = -90 + side * rnd.uniform(20, 95)
            dist = rnd.uniform(0.0, 0.08) * w
            cx = ox + math.cos(math.radians(ang)) * dist + side * rnd.uniform(-0.02, 0.05) * w
            cy = oy + math.sin(math.radians(ang)) * dist * 0.8 + rnd.uniform(-0.04, 0.06) * h
            ln = rnd.uniform(0.05, 0.1) * w
            draw_leaf(canvas, cx, cy, ln, ln * rnd.uniform(0.38, 0.48), ang + rnd.uniform(-15, 15),
                      scale(rnd.choice(greens), lightk), sheen=0.3, highlight=leaf_hi, light=1.4, dark=0.42,
                      rim=None if night else (SUN_RIM, 170))
        for k in range(4):
            fx = ox + side * rnd.uniform(0.0, 0.08) * w
            fy = oy + rnd.uniform(-0.12, 0.1) * h
            draw_flower(canvas, fx, fy, rnd.uniform(0.018, 0.027) * w, rot=rnd.uniform(0, 72), light=flower_light)
    # Small leaves tucked along the top.
    for _ in range(16):
        x = rnd.uniform(w * 0.2, w * 0.8)
        ln = rnd.uniform(0.025, 0.045) * w
        draw_leaf(canvas, x, h * rnd.uniform(0.26, 0.33), ln, ln * 0.42, -90 + rnd.uniform(-65, 65),
                  scale(rnd.choice(greens), lightk * 0.92), sheen=0.3, veins=False, highlight=leaf_hi, light=1.4)
    img = canvas.resize((LW, LH), Image.LANCZOS)
    return fade_alpha(img, bottom_len=0.5)


# ---------------------------------------------------------------- review


def review(layers, out_dir):
    """Approximates the Day lobby on a 411x914 screen (x2.6)."""
    sw, sh = 1080, 2400
    base = layers["day_base"].convert("RGBA").resize((sw, int(sw * H / W)))
    sheet = Image.new("RGBA", (sw, sh), (0, 0, 0, 255))
    sheet.alpha_composite(base, (0, (sh - base.height) // 2))

    def put(name, width_f, anchor, dx=0.0, dy=0.0):
        im = layers[name]
        wpx = int(sw * width_f)
        im = im.resize((wpx, int(wpx * im.height / im.width)), Image.LANCZOS)
        x = {"l": 0, "r": sw - wpx, "c": (sw - wpx) // 2}[anchor[1]] + dx * sw
        y = {"t": 0, "b": sh - im.height}[anchor[0]] + dy * sh
        composite_at(sheet, im, x, y)

    put("day_path", 1.04, "bc")
    put("day_foliage_tr", 0.66, "tr", 0.12, -0.035)
    put("day_foliage_tl", 0.62, "tl", -0.08, -0.03)
    put("day_foliage_ml", 0.42, "tl", -0.1, 0.36)
    put("day_foliage_mr", 0.42, "tr", 0.1, 0.42)
    put("day_foliage_bl", 0.5, "bl", -0.09, 0.03)
    put("day_foliage_br", 0.52, "br", 0.1, 0.035)
    put("day_ledge", 1.0, "tc", 0, 0.27)
    out_dir.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").resize((540, 1200), Image.LANCZOS).save(out_dir / "lobby-day-sheet.png")
    night = Image.new("RGBA", (1080, 360), (6, 44, 37, 255))
    night.alpha_composite(layers["night_ledge"])
    night.convert("RGB").save(out_dir / "lobby-night-ledge.png")


def main():
    layers = {
        "day_base": save(day_base(), "day/day_base.webp", quality=80),
        "day_path": save(day_path(), "day/day_path.webp"),
    }
    for name, img in foliage_set().items():
        layers[name] = save(img, f"day/{name}.webp")
    layers["day_ledge"] = save(ledge(night=False), "day/day_ledge.webp")
    layers["night_ledge"] = save(ledge(night=True), "night_ledge.webp")
    if "--review" in sys.argv:
        review(layers, Path(sys.argv[sys.argv.index("--review") + 1]))


if __name__ == "__main__":
    main()
