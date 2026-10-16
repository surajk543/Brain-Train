#!/usr/bin/env python3
"""Render the home/lobby screen's background art (night garden).

Everything is drawn procedurally with Pillow (no numpy, no licensed art) and
written as optimized WebP layers the app stacks at runtime, so the lobby is
never blank offline and adapts to any screen aspect:

  assets/lobby/night_base.webp                opaque emerald forest (cover fit)
  assets/lobby/night_path.webp                cobblestone path, bottom-anchored
  assets/lobby/night_foliage_{tl,tr,bl,br}.webp   corner foliage
  assets/lobby/night_lantern.webp             glowing hanging lantern
  assets/lobby/button_leaf.webp               leaves for the button ends
  assets/lobby/leaf_sprites.webp              drifting leaf/petal sprites (crisp
                                              row, then a softened row)

Lighting that must stay tunable (lantern glow, calm centre, vignette), the
frosted-glass tagline panel and the fireflies are drawn by Flutter on top (see LobbyTheme in lib/app/theme.dart).

Usage: python3 tool/assets/make_lobby_art.py
Also writes a review composite to art/review/lobby-night-sheet.png.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/lobby"
SS = 2  # supersampling for crisp foliage edges

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
    # Pillow's gradient is 181 at the edge midpoints and 255 in the corners;
    # rescale so the inscribed ellipse edge is exactly 0.
    g = Image.radial_gradient("L").point(lambda v: min(255, v * 255 // 181))
    g = ImageChops.invert(g.resize((w, h), Image.BILINEAR))
    if power != 1.0:
        g = g.point(lambda v: clamp(255 * (v / 255) ** power))
    return g


def glow_layer(r, color, alpha=255, power=1.6, squash=1.0):
    w, h = max(2, int(r * 2)), max(2, int(r * 2 * squash))
    m = radial_mask(w, h, power).point(lambda v: v * alpha // 255)
    layer = Image.new("RGBA", (w, h), color + (0,))
    layer.putalpha(m)
    return layer


def add_glow(canvas, cx, cy, r, color, alpha=255, power=1.6, squash=1.0):
    g = glow_layer(r, color, alpha, power, squash)
    composite_at(canvas, g, cx - g.width / 2, cy - g.height / 2)


def screen_light(rgb, mask, color):
    """Screen-blends `color` into an RGB image, weighted by an L mask."""
    light = Image.merge("RGB", [m.point(lambda v, c=c: v * c // 255) for m, c in zip((mask, mask, mask), color)])
    return ImageChops.screen(rgb, light)


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
               highlight=(255, 255, 236), light_from=(0.3, 0.25), tip=0.85):
    """A glossy leaf on its own small canvas; returns (layer, (x0, y0))."""
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
        rib = scale(base, 1.9)
        d.line((cx - ux * length * 0.48, cy - uy * length * 0.48, cx + ux * length * 0.45, cy + uy * length * 0.45),
               fill=rib + (255,), width=max(1, int(width * 0.035)))
        for k in (-0.32, -0.14, 0.04, 0.22):
            px, py = cx + ux * length * k, cy + uy * length * k
            for side in (1, -1):
                ex = px + (ux * 0.5 + nx * side * 0.85) * width * 0.42
                ey = py + (uy * 0.5 + ny * side * 0.85) * width * 0.42
                d.line((px, py, ex, ey), fill=rib + (90,), width=max(1, int(width * 0.016)))
    if sheen:
        sm = Image.new("L", size, 0)
        ImageDraw.Draw(sm).polygon(
            [(x - x0, y - y0) for x, y in leaf_points(nx * width * 0.14, ny * width * 0.14, length * 0.68, width * 0.3, angle)],
            fill=int(255 * sheen))
        sm = sm.filter(ImageFilter.GaussianBlur(width * 0.07 + 1))
        layer = Image.composite(Image.new("RGBA", size, highlight + (255,)), layer, ImageChops.multiply(sm, mask))
    layer.putalpha(mask)
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
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


def flower_layer(r, *, petals=5, rot=0.0, tint=(255, 250, 236), shade=(222, 206, 168), centre=(232, 176, 58),
                 blur=0.0, light=1.0):
    """A cream five-petal flower (plumeria-like) on its own canvas."""
    pad = int(blur * 3 + 4)
    size = int(r * 2 + pad * 2)
    c = size / 2
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for k in range(petals):
        ang = rot + k * 360 / petals
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).polygon(petal_points(c, c, r, r * 0.78, ang), fill=255)
        # Petal shading: deeper toward the centre and on the lower side.
        g = radial_mask(int(r * 2.2), int(r * 2.2), 0.8)
        sh = Image.new("L", (size, size), 0)
        a = math.radians(ang)
        sh.paste(g, (int(c + math.cos(a) * r * 0.62 - g.width / 2), int(c + math.sin(a) * r * 0.62 - g.height / 2 - r * 0.1)))
        fill = Image.composite(Image.new("RGB", (size, size), scale(tint, light)),
                               Image.new("RGB", (size, size), scale(shade, light)), sh).convert("RGBA")
        fill.putalpha(mask)
        # Thin darker edge separating overlapping petals.
        edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(edge).line(petal_points(c, c, r, r * 0.78, ang) + [petal_points(c, c, r, r * 0.78, ang)[0]],
                                  fill=scale(shade, 0.8 * light) + (110,), width=max(1, int(r * 0.03)))
        layer.alpha_composite(fill)
        layer.alpha_composite(edge)
    d = ImageDraw.Draw(layer)
    cr = r * 0.22
    d.ellipse((c - cr, c - cr, c + cr, c + cr), fill=scale(centre, light) + (255,))
    hi = scale(mix(centre, (255, 240, 180), 0.6), light)
    d.ellipse((c - cr * 0.55, c - cr * 0.65, c + cr * 0.25, c + cr * 0.1), fill=hi + (255,))
    for k in range(7):
        a = math.radians(k * 360 / 7 + rot)
        px, py = c + math.cos(a) * cr * 1.35, c + math.sin(a) * cr * 1.35
        d.ellipse((px - r * 0.035, py - r * 0.035, px + r * 0.035, py + r * 0.035), fill=scale((196, 130, 40), light) + (255,))
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return layer


def draw_flower(canvas, cx, cy, r, **kw):
    f = flower_layer(r, **kw)
    composite_at(canvas, f, cx - f.width / 2, cy - f.height / 2)


def draw_curl(canvas, cx, cy, radius, start, sweep, width, color=(214, 168, 72), glow=(255, 214, 120, 110), turns=1.0):
    """A gold spiral tendril."""
    pts = []
    n = 180
    for i in range(n):
        t = i / (n - 1)
        ang = math.radians(start + sweep * t * turns)
        r = radius * (1 - 0.78 * t)
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    g = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(g).line(pts, fill=glow, width=int(width * 3))
    canvas.alpha_composite(g.filter(ImageFilter.GaussianBlur(width * 1.4)))
    d = ImageDraw.Draw(canvas)
    d.line(pts, fill=color + (255,), width=int(width), joint="curve")
    d.line(pts, fill=(255, 232, 160, 210), width=max(1, int(width * 0.45)), joint="curve")
    return pts


def disc(r, color, alpha, rim=1.25, blur_frac=0.08):
    pad = int(r * 0.4 + 4)
    size = int(r * 2 + pad * 2)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c = size / 2
    d.ellipse((c - r, c - r, c + r, c + r), fill=color + (clamp(alpha),))
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
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def fade_alpha(img, top=0.0, top_len=0.0, bottom_len=0.0, left_len=0.0, right_len=0.0):
    """Multiplies alpha by linear ramps at the edges (fractions of size)."""
    w, h = img.size
    ramp = Image.new("L", (w, h), 255)
    px = ramp.load()
    for y in range(h):
        ty = y / h
        fy = 1.0
        if top_len and ty < top + top_len:
            fy = max(0.0, (ty - top) / top_len)
        if bottom_len and ty > 1 - bottom_len:
            fy *= max(0.0, (1 - ty) / bottom_len)
        for x in range(w):
            tx = x / w
            f = fy
            if left_len and tx < left_len:
                f *= tx / left_len
            if right_len and tx > 1 - right_len:
                f *= (1 - tx) / right_len
            px[x, y] = int(255 * f * f * (3 - 2 * f))
    a = ImageChops.multiply(img.getchannel("A"), ramp)
    img.putalpha(a)
    return img


def save(img, name, quality=84, lossless=False):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.webp"
    if img.mode == "RGBA" and img.getchannel("A").getextrema() == (255, 255):
        img = img.convert("RGB")
    img.save(path, "WEBP", quality=quality, method=6, lossless=lossless, alpha_quality=90)
    print(f"{path.relative_to(ROOT)}  {img.size}  {path.stat().st_size // 1024} KB")
    return img


# ---------------------------------------------------------------- bases

W, H = 1080, 2340


def night_base():
    rnd = random.Random(202)
    img = vertical_gradient(W, H, [
        (0.0, (8, 40, 34)),
        (0.18, (10, 58, 46)),
        (0.42, (10, 68, 51)),
        (0.7, (8, 54, 42)),
        (1.0, (5, 34, 29)),
    ]).convert("RGBA")
    # Tree trunks fading into mist.
    trunks = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    td = ImageDraw.Draw(trunks)
    for x, w_, shade in [(70, 70, 0.6), (250, 34, 0.8), (W - 120, 80, 0.6), (W - 300, 40, 0.8), (520, 22, 0.9),
                         (760, 28, 0.85)]:
        c = scale((4, 26, 22), shade)
        td.polygon([(x - w_ / 2, 0), (x + w_ / 2, 0), (x + w_ * 0.7, H * 0.8), (x - w_ * 0.7, H * 0.8)], fill=c + (170,))
    img.alpha_composite(trunks.filter(ImageFilter.GaussianBlur(18)))
    blob_mass(img, rnd, 44, (-100, 80, W + 100, 900), 220, 420, [(10, 56, 44), (14, 66, 50), (8, 48, 38)], 32)
    blob_mass(img, rnd, 46, (-150, 400, 260, 1950), 240, 460, [(4, 32, 27), (6, 40, 32), (8, 46, 36)], 30)
    blob_mass(img, rnd, 46, (W - 260, 400, W + 150, 1950), 240, 460, [(4, 32, 27), (6, 40, 32), (8, 46, 36)], 30)
    # Faint moonlit mist at the top-centre.
    rgb = img.convert("RGB")
    mist = Image.new("L", (W, H), 0)
    mm = radial_mask(int(W * 1.6), int(H * 0.6), 1.5)
    mist.paste(mm, (int(W * 0.5 - mm.width / 2), int(H * 0.02 - mm.height / 2)))
    rgb = screen_light(rgb, mist.point(lambda v: v * 70 // 255), (150, 210, 190))
    img = rgb.convert("RGBA")
    # Bokeh: deep teal discs and a few warm distant lantern lights.
    bokeh(img, rnd, 60, (0, 0, W, 1700), 14, 54, [(40, 110, 90), (30, 96, 80), (60, 130, 104)], 22, 60)
    side = lambda x, y: (abs(x - W / 2) / (W / 2)) ** 1.2
    bokeh(img, rnd, 46, (0, 500, W, 1700), 6, 22, [(255, 196, 106), (246, 176, 86), (255, 216, 140)], 50, 140,
          weight=side, blur_frac=0.14)
    calm = glow_layer(W * 0.62, (3, 26, 21), 110, power=1.2, squash=1.5)
    composite_at(img, calm, W * 0.5 - calm.width / 2, H * 0.55 - calm.height / 2)
    return img.convert("RGB")




# ---------------------------------------------------------------- path

PW, PH = 1080, 640


def stone_mask(poly, size, round_px):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    m = m.filter(ImageFilter.GaussianBlur(round_px))
    return m.point(lambda v: 255 if v > 150 else 0).filter(ImageFilter.GaussianBlur(1.0))


def mottle(size, rnd, count, rmin, rmax, blur):
    """Large-scale tonal variation mask."""
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    w, h = size
    for _ in range(count):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        r = rnd.uniform(rmin, rmax)
        d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=rnd.randint(60, 200))
    return m.filter(ImageFilter.GaussianBlur(blur))


def path_layer():
    """Perspective cobblestone path catching lantern light, fading upward."""
    rnd = random.Random(303)
    w, h = PW * SS, PH * SS
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    z_far, z_near = 9.0, 1.35

    def y_of(z):
        return (1 / z - 1 / z_far) / (1 / z_near - 1 / z_far) * h * 1.06 + h * 0.04

    def x_of(u, z):  # u in [-1, 1] across the path at depth z
        k = (1 / z - 1 / z_far) / (1 / z_near - 1 / z_far)
        return w / 2 + u * (0.2 + 0.62 * k) * w

    # Dark loam between the stones, feathered at the sides.
    ground = vertical_gradient(w, h, [(0, (10, 44, 34)), (1, (6, 30, 24))]).convert("RGBA")
    gm = Image.new("L", (w, h), 0)
    ImageDraw.Draw(gm).polygon([(x_of(-1.35, z_far), y_of(z_far)), (x_of(1.35, z_far), y_of(z_far)),
                                (x_of(1.5, 1.0), h * 1.3), (x_of(-1.5, 1.0), h * 1.3)], fill=255)
    ground.putalpha(gm.filter(ImageFilter.GaussianBlur(40 * SS)))
    canvas.alpha_composite(ground)

    rows = 17
    zs = [z_far - (z_far - z_near) * (j / rows) ** 0.75 for j in range(rows + 1)]
    phase = [rnd.uniform(0, 6.3) for _ in zs]

    def row_z(j, u):  # wavy joint line between rows
        dz = (zs[max(0, j - 1)] - zs[min(rows, j + 1)]) * 0.06
        return zs[j] + dz * math.sin(u * 3.1 + phase[j]) + dz * 0.5 * math.sin(u * 7.3 + phase[j] * 2)

    base = (46, 54, 52)
    moss_col = (22, 66, 42)
    for j in range(rows):
        n = rnd.randint(9, 13)
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
            gap = 0.86
            poly = [(cxp + (x - cxp) * (gap + 0.06 * (abs(y - cyp) < 1)), cyp + (y - cyp) * gap) for x, y in poly]
            xs, ys = [p[0] for p in poly], [p[1] for p in poly]
            bx0, by0 = int(min(xs)) - 24, int(min(ys)) - 24
            bw, bh = int(max(xs)) - bx0 + 24, int(max(ys)) - by0 + 24
            if bx0 > w or bx0 + bw < 0:
                continue
            local = [(x - bx0, y - by0) for x, y in poly]
            m = stone_mask(local, (bw, bh), max(3, row_h * 0.22))
            tone = scale(mix(base, (60, 62, 54), rnd.uniform(0, 0.6)), rnd.uniform(0.85, 1.1))
            g = vertical_gradient(bw, bh, [(0, scale(tone, 1.22)), (0.35, tone), (1, scale(tone, 0.62))]).convert("RGBA")
            mt = mottle((bw, bh), rnd, 8, bw * 0.08, bw * 0.22, bw * 0.06 + 2)
            g = Image.composite(Image.new("RGBA", (bw, bh), scale(tone, 0.8) + (255,)), g, mt.point(lambda v: v // 2))
            tex = Image.new("L", (bw, bh), 0)
            td = ImageDraw.Draw(tex)
            for _ in range(int(bw * bh / 900)):
                x, y = rnd.uniform(0, bw), rnd.uniform(0, bh)
                rr = rnd.uniform(0.8, 2.0) * SS
                td.ellipse((x - rr, y - rr, x + rr, y + rr), fill=rnd.randint(20, 60))
            g = Image.composite(Image.new("RGBA", (bw, bh), scale(tone, 0.55) + (255,)), g, tex.filter(ImageFilter.GaussianBlur(0.8)))
            # Moss along the joints and in one or two patches.
            moss = Image.new("L", (bw, bh), 0)
            md = ImageDraw.Draw(moss)
            for _ in range(rnd.randint(3, 8)):
                edge = rnd.random()
                x = rnd.uniform(0, bw) if edge < 0.6 else rnd.choice((rnd.uniform(0, bw * 0.15), rnd.uniform(bw * 0.85, bw)))
                y = rnd.choice((rnd.uniform(0, bh * 0.25), rnd.uniform(bh * 0.75, bh))) if edge < 0.6 else rnd.uniform(0, bh)
                rr = rnd.uniform(0.05, 0.16) * bw
                md.ellipse((x - rr, y - rr * 0.5, x + rr, y + rr * 0.5), fill=rnd.randint(140, 230))
            moss = moss.filter(ImageFilter.GaussianBlur(3 * SS))
            mcol = vertical_gradient(bw, bh, [(0, scale(moss_col, 1.25)), (1, scale(moss_col, 0.8))]).convert("RGBA")
            g = Image.composite(mcol, g, moss)
            # Damp sheen on the far (upper) rim of each cobble.
            rim = Image.new("L", (bw, bh), 0)
            ImageDraw.Draw(rim).line(local[:6], fill=90, width=max(2, int(row_h * 0.06)))
            rim = ImageChops.multiply(rim.filter(ImageFilter.GaussianBlur(row_h * 0.04 + 1)), m)
            g = Image.composite(Image.new("RGBA", (bw, bh), (170, 190, 170, 255)), g, rim)
            g.putalpha(m)
            sh = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
            sh.putalpha(m.point(lambda v: v * 130 // 255))
            composite_at(canvas, sh.filter(ImageFilter.GaussianBlur(4 * SS)), bx0 + 2 * SS, by0 + 4 * SS)
            composite_at(canvas, g, bx0, by0)
    # Grass and small leaves along both edges.
    for side in (-1, 1):
        for _ in range(22):
            t = rnd.uniform(0.0, 1.0)
            z = z_far - (z_far - z_near) * t
            x = x_of(side * rnd.uniform(1.0, 1.35), z)
            y = y_of(z)
            ln = (24 + 120 * t) * SS / 2
            draw_leaf(canvas, x, y - ln * 0.3, ln, ln * 0.42, -90 + side * rnd.uniform(10, 65) + rnd.uniform(-20, 20),
                      scale(rnd.choice(NIGHT_GREENS), 0.9), veins=t > 0.5, sheen=0.2, highlight=(200, 236, 220),
                      blur=(1 - t) * 3 * SS)
    img = canvas.resize((PW, PH), Image.LANCZOS)
    rgb, a = img.convert("RGB"), img.getchannel("A")
    # Warm lantern light pooling on the stones from both sides.
    light = Image.new("L", (PW, PH), 0)
    for cx, cy, rx, ry, v in [(-PW * 0.05, PH * 0.4, PW * 0.62, PH * 0.8, 230), (PW * 1.05, PH * 0.15, PW * 0.58, PH * 0.65, 210)]:
        m = radial_mask(int(rx * 2), int(ry * 2), 1.5).point(lambda q, v=v: q * v // 255)
        tmp = Image.new("L", (PW, PH), 0)
        tmp.paste(m, (int(cx - rx), int(cy - ry)))
        light = ImageChops.lighter(light, tmp)
    warm = Image.merge("RGB", [light.point(lambda v, c=c: v * c // 255) for c in (255, 168, 76)])
    rgb = ImageChops.add(rgb, ImageChops.multiply(warm, rgb.point(lambda v: min(255, v * 3))))
    # Foreground falls into shade toward the bottom edge.
    shade = vertical_gradient(PW, PH, [(0, (255,) * 3), (0.6, (235,) * 3), (1, (150,) * 3)])
    rgb = ImageChops.multiply(rgb, shade)
    img = rgb.convert("RGBA")
    img.putalpha(a)
    # Depth of field on the far rows and the nearest edge.
    soft = img.filter(ImageFilter.GaussianBlur(3))
    fm = vertical_gradient(PW, PH, [(0, (255,) * 3), (0.3, (0,) * 3), (0.85, (0,) * 3), (1, (200,) * 3)]).convert("L")
    img = Image.composite(soft, img, fm)
    return fade_alpha(img, top_len=0.3)


# ---------------------------------------------------------------- foliage

# Fresh leaf greens for the leaves at the button ends.
LEAF_GREENS = [(52, 132, 60), (66, 148, 66), (40, 116, 56), (84, 160, 70), (34, 104, 52)]
# Dark, glossy night foliage.
NIGHT_GREENS = [(22, 86, 60), (28, 100, 68), (16, 72, 52), (34, 112, 74), (14, 62, 48)]


def foliage(w, h, origin, direction, seed, *, leaves=30, flowers=(), spread=62, reach_k=1.0, size_k=1.0,
            back_blur=8, front_blur=0.0, curls=0, broad=False):
    """Leaves fanning from `origin` toward `direction` (degrees).

    flowers: list of (angle offset, distance fraction, radius fraction, blur).
    """
    rnd = random.Random(seed)
    canvas = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    ox, oy = origin[0] * SS, origin[1] * SS
    reach = max(w, h) * SS * reach_k
    layers = [(leaves // 2, back_blur * SS, 0.62, 1.2), (leaves - leaves // 2, front_blur * SS, 1.0, 1.0)]
    for li, (count, blur, dim, sk) in enumerate(layers):
        for _ in range(count):
            ang = direction + rnd.uniform(-spread, spread)
            dist = rnd.uniform(0.02, 0.55) * reach * (0.8 if li else 1)
            cx = ox + math.cos(math.radians(ang)) * dist
            cy = oy + math.sin(math.radians(ang)) * dist
            length = rnd.uniform(0.2, 0.36) * reach * sk * size_k * (1 - dist / reach * 0.55)
            width = length * (rnd.uniform(0.5, 0.62) if broad else rnd.uniform(0.38, 0.48))
            base = scale(rnd.choice(NIGHT_GREENS), dim)
            draw_leaf(canvas, cx, cy, length, width, ang + rnd.uniform(-30, 30), base, blur=blur, sheen=0.4,
                      highlight=(200, 236, 220), light=1.55, dark=0.35)
        if li == 0:
            for _ in range(curls):
                cx = ox + math.cos(math.radians(direction)) * reach * rnd.uniform(0.25, 0.4)
                cy = oy + math.sin(math.radians(direction)) * reach * rnd.uniform(0.25, 0.4)
                draw_curl(canvas, cx, cy, reach * 0.09, rnd.uniform(0, 360), rnd.choice((-420, 420)), 2.4 * SS,
                          color=(196, 150, 62))
    for ang_off, dist_f, r_f, blur in flowers:
        ang = direction + ang_off
        dist = dist_f * reach
        fl = flower_layer(r_f * reach, rot=rnd.uniform(0, 72), blur=blur * SS, light=0.86, tint=(250, 242, 218))
        composite_at(canvas, fl, ox + math.cos(math.radians(ang)) * dist - fl.width / 2,
                     oy + math.sin(math.radians(ang)) * dist - fl.height / 2)
    return canvas.resize((w, h), Image.LANCZOS)


def foliage_set():
    return {
        "night_foliage_tl": foliage(760, 900, (0, 0), 52, 12, leaves=40, spread=58, flowers=[(-6, 0.28, 0.07, 0)], curls=1),
        "night_foliage_tr": foliage(780, 1000, (780, 0), 128, 24, leaves=46, spread=60, size_k=1.15, broad=True),
        "night_foliage_bl": foliage(640, 640, (0, 640), -48, 38, leaves=26, spread=50, back_blur=12, front_blur=4.5),
        "night_foliage_br": foliage(660, 660, (660, 660), -128, 42, leaves=28, spread=50, back_blur=12, front_blur=4.5),
    }


# ---------------------------------------------------------------- lantern

def lantern():
    """A bronze hanging lantern with warm glowing panes and a soft halo."""
    w, h = 360, 820
    c = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    S = SS
    cx = w * S / 2
    # Halo.
    add_glow(c, cx, 520 * S, 170 * S, (255, 176, 74), 150, power=1.8)
    add_glow(c, cx, 520 * S, 90 * S, (255, 214, 130), 150, power=1.4)
    d = ImageDraw.Draw(c)
    metal = (44, 34, 22)
    metal_hi = (150, 104, 52)
    # Chain up to the branch above.
    for i in range(0, 380, 22):
        y = i * S
        d.ellipse((cx - 5 * S, y, cx + 5 * S, y + 16 * S), outline=metal + (255,), width=3 * S)
    # Hook ring and roof.
    d.ellipse((cx - 14 * S, 372 * S, cx + 14 * S, 398 * S), outline=metal + (255,), width=5 * S)
    roof = [(cx - 16 * S, 400 * S), (cx + 16 * S, 400 * S), (cx + 92 * S, 448 * S), (cx + 104 * S, 462 * S),
            (cx - 104 * S, 462 * S), (cx - 92 * S, 448 * S)]
    d.polygon(roof, fill=metal + (255,))
    d.line([(cx - 92 * S, 449 * S), (cx - 14 * S, 403 * S)], fill=metal_hi + (255,), width=3 * S)
    d.polygon([(cx - 10 * S, 384 * S), (cx + 10 * S, 384 * S), (cx + 16 * S, 400 * S), (cx - 16 * S, 400 * S)],
              fill=metal + (255,))
    # Glass body: three visible panes (centre facing, sides foreshortened).
    top, bot = 466 * S, 590 * S
    body = [(cx - 78 * S, top), (cx + 78 * S, top), (cx + 66 * S, bot), (cx - 66 * S, bot)]
    gm = Image.new("L", c.size, 0)
    ImageDraw.Draw(gm).polygon(body, fill=255)
    glass = Image.new("RGBA", c.size, (255, 150, 52, 255))
    core = glow_layer(80 * S, (255, 246, 196), 255, power=1.1, squash=1.2)
    composite_at(glass, core, cx - core.width / 2, 528 * S - core.height / 2)
    glass.putalpha(gm)
    c.alpha_composite(glass)
    # Flame.
    fl = glow_layer(16 * S, (255, 255, 236), 255, power=0.8, squash=1.8)
    composite_at(c, fl, cx - fl.width / 2, 540 * S - fl.height / 2)
    # Frame bars.
    for x0, x1 in [(-78, -66), (-28, -24), (24, 28), (78, 66)]:
        d.line([(cx + x0 * S, top), (cx + x1 * S, bot)], fill=metal + (255,), width=7 * S)
    d.line([(cx - 80 * S, top), (cx + 80 * S, top)], fill=metal + (255,), width=8 * S)
    d.line([(cx - 68 * S, bot), (cx + 68 * S, bot)], fill=metal + (255,), width=8 * S)
    d.line([(cx - 74 * S, 528 * S), (cx + 74 * S, 528 * S)], fill=metal + (180,), width=3 * S)
    # Warm rim light on the frame.
    for x0, x1 in [(-28, -24), (24, 28)]:
        d.line([(cx + (x0 + 3) * S, top + 4 * S), (cx + (x1 + 3) * S, bot - 4 * S)], fill=metal_hi + (220,), width=2 * S)
    # Base and finial.
    d.polygon([(cx - 70 * S, bot + 2 * S), (cx + 70 * S, bot + 2 * S), (cx + 46 * S, bot + 24 * S), (cx - 46 * S, bot + 24 * S)],
              fill=metal + (255,))
    d.ellipse((cx - 9 * S, bot + 22 * S, cx + 9 * S, bot + 40 * S), fill=metal + (255,))
    d.line([(cx - 64 * S, bot + 4 * S), (cx + 64 * S, bot + 4 * S)], fill=metal_hi + (255,), width=2 * S)
    # Light spilling down from the open base.
    add_glow(c, cx, (bot + 120 * S), 110 * S, (255, 170, 70), 70, power=1.6, squash=0.7)
    img = c.resize((w, h), Image.LANCZOS)
    return fade_alpha(img, top_len=0.08)


# ---------------------------------------------------------------- small decor

def button_leaf():
    """Leaves fanning left from a point at the right edge (button ends)."""
    w, h = 240, 170
    c = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    S = SS
    ox, oy = 214 * S, 92 * S
    for ang, ln, col in [(-158, 150, LEAF_GREENS[4]), (165, 140, LEAF_GREENS[0]), (-188, 170, LEAF_GREENS[1]),
                         (-140, 110, LEAF_GREENS[3])]:
        a = math.radians(ang)
        draw_leaf(c, ox + math.cos(a) * ln * S * 0.5, oy + math.sin(a) * ln * S * 0.5, ln * S, ln * S * 0.42, ang, col,
                  sheen=0.6)
    return c.resize((w, h), Image.LANCZOS)


# ---------------------------------------------------------------- flowing leaves

LEAF_CELL = 160
LEAF_SPRITES = 6  # columns: 4 greens, gold-tinted leaf, cream petal


def leaf_sprite(index, blur):
    """One drifting-leaf sprite, pointing up, centred in its cell."""
    c = LEAF_CELL * SS
    cell = Image.new("RGBA", (c, c), (0, 0, 0, 0))
    cx = cy = c / 2
    length, width = c * 0.7, c * 0.36
    if index < 4:
        base = [LEAF_GREENS[1], LEAF_GREENS[0], (30, 110, 70), LEAF_GREENS[3]][index]
        w = width * [1.0, 0.82, 1.1, 0.9][index]
        draw_leaf(cell, cx, cy, length, w, -90, base, sheen=0.6, tip=[0.85, 0.7, 0.95, 0.8][index])
    elif index == 4:
        draw_leaf(cell, cx, cy, length * 0.92, width, -90, (196, 150, 54), sheen=0.7, highlight=(255, 240, 190),
                  light=1.45, dark=0.55)
    else:
        m = Image.new("L", (c, c), 0)
        pts = petal_points(cx, cy + length * 0.32, length * 0.62, length * 0.42, -90)
        ImageDraw.Draw(m).polygon(pts, fill=255)
        g = vertical_gradient(c, c, [(0, (255, 252, 240)), (0.55, (248, 236, 206)), (1, (222, 204, 160))]).convert("RGBA")
        g.putalpha(m.filter(ImageFilter.GaussianBlur(1)))
        cell.alpha_composite(g)
    cell = cell.resize((LEAF_CELL, LEAF_CELL), Image.LANCZOS)
    if blur:
        # Premultiplied, so transparent black does not darken the edges.
        cell = cell.convert("RGBa").filter(ImageFilter.GaussianBlur(blur)).convert("RGBA")
    return cell


def leaf_atlas():
    """Row 0: crisp sprites (near leaves). Row 1: the same, softened (far)."""
    atlas = Image.new("RGBA", (LEAF_CELL * LEAF_SPRITES, LEAF_CELL * 2), (0, 0, 0, 0))
    for row, blur in enumerate((0, 7)):
        for i in range(LEAF_SPRITES):
            atlas.alpha_composite(leaf_sprite(i, blur), (i * LEAF_CELL, row * LEAF_CELL))
    return atlas


# ---------------------------------------------------------------- review


def review(layers):
    """Approximates the app's layout on a 411x914 screen (x2.6)."""
    sw, sh = 1080, 2400
    base = layers["night_base"].convert("RGBA").resize((sw, int(sw * H / W)))
    sheet = Image.new("RGBA", (sw, sh), (0, 0, 0, 255))
    sheet.alpha_composite(base, (0, (sh - base.height) // 2))

    def put(name, width_f, anchor, dx=0.0, dy=0.0, flip=False):
        im = layers[name]
        if flip:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        wpx = int(sw * width_f)
        im = im.resize((wpx, int(wpx * im.height / im.width)), Image.LANCZOS)
        x = {"l": 0, "r": sw - wpx, "c": (sw - wpx) // 2}[anchor[1]] + dx * sw
        y = {"t": 0, "b": sh - im.height}[anchor[0]] + dy * sh
        composite_at(sheet, im, x, y)

    put("night_path", 1.04, "bc")
    put("night_lantern", 0.18, "tl", -0.05, 0.3)
    put("night_lantern", 0.18, "tr", 0.05, 0.5, flip=True)
    put("night_foliage_tr", 0.66, "tr", 0.12, -0.035)
    put("night_foliage_tl", 0.62, "tl", -0.08, -0.03)
    put("night_foliage_bl", 0.5, "bl", -0.09, 0.03)
    put("night_foliage_br", 0.52, "br", 0.1, 0.035)
    (ROOT / "art/review").mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").resize((540, 1200), Image.LANCZOS).save(ROOT / "art/review/lobby-night-sheet.png")


def main():
    layers = {"night_base": save(night_base(), "night_base", quality=80), "night_path": save(path_layer(), "night_path")}
    for name, img in foliage_set().items():
        layers[name] = save(img, name)
    layers["night_lantern"] = save(lantern(), "night_lantern")
    layers["button_leaf"] = save(button_leaf(), "button_leaf", quality=90)
    save(leaf_atlas(), "leaf_sprites", quality=90)
    review(layers)


if __name__ == "__main__":
    main()
