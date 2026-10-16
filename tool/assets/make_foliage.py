#!/usr/bin/env python3
"""Render the gameplay screen's botanical edge decoration.

Glossy dark-green leaf clusters with thin gold vine curls and small cream
flowers, as transparent WebP layers the game places at the screen edges.
Back leaves are darker and blurred (depth of field); front leaves are crisp
with a specular streak along the midrib.

Usage: python3 tool/assets/make_foliage.py
Writes: assets/decor/foliage_{top_left,bottom_left,bottom_right,right}.webp
        art/review/foliage-sheet.png (all layers on the emerald felt)
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SS = 2  # supersampling

GREENS = [(20, 74, 42), (26, 84, 46), (16, 64, 38), (30, 92, 50), (22, 80, 52)]
LIGHT = (-0.45, -0.9)  # light from the top (slightly left), screen coordinates


def scale(color, k, alpha=None):
    c = tuple(max(0, min(255, int(v * k))) for v in color[:3])
    return c + ((alpha,) if alpha is not None else ())


def leaf_halves(cx, cy, length, width, angle, bend, steps=48):
    """Two polygons (one per side of the midrib) and the midrib polyline."""
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)

    def to_canvas(x, y):
        return (cx + x * ca - y * sa, cy + x * sa + y * ca)

    def mid(t):
        return bend * length * (1 - t * t) * 0.5

    def half_width(t):
        # Broad near the base, long pointed tip.
        u = (t + 1) / 2
        return width / 2 * (math.sin(math.pi * u ** 0.85) ** 0.9)

    rib = [to_canvas(t * length / 2, mid(t)) for t in (-1 + 2 * i / steps for i in range(steps + 1))]
    side_a, side_b = [], []
    for i in range(steps + 1):
        t = -1 + 2 * i / steps
        side_a.append(to_canvas(t * length / 2, mid(t) + half_width(t)))
        side_b.append(to_canvas(t * length / 2, mid(t) - half_width(t)))
    return side_a + rib[::-1], side_b + rib[::-1], rib


def axis_gradient(size, angle):
    """L image rising from 0 at the leaf base to 255 at the tip."""
    big = Image.linear_gradient("L").resize((size * 2, size * 2))
    big = big.rotate(90 - angle, resample=Image.BILINEAR)
    o = size // 2
    return big.crop((o, o, o + size, o + size))


def leaf(length, width, angle, base, rng, blur=0.0, dim=1.0):
    """A leaf on its own transparent square, with its base at the centre."""
    pad = int(blur * 3 + 6)
    size = int(length * 2 + pad * 2)
    c = size / 2
    # Base of the leaf at the centre: shift the leaf centre along its axis.
    a = math.radians(angle)
    cx, cy = c + math.cos(a) * length / 2, c + math.sin(a) * length / 2
    bend = rng.uniform(-0.1, 0.1)
    poly_a, poly_b, rib = leaf_halves(cx, cy, length, width, angle, bend)
    base = scale(base, dim)

    mask_a = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask_a).polygon(poly_a, fill=255)
    mask_b = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask_b).polygon(poly_b, fill=255)
    full = ImageChops.lighter(mask_a, mask_b)

    # Which half faces the light.
    nx, ny = -math.sin(a), math.cos(a)
    a_lit = nx * LIGHT[0] + ny * LIGHT[1] > 0
    grad = axis_gradient(size, angle)

    def half_fill(lit):
        tip = scale(base, 1.55 if lit else 0.95)
        root = scale(base, 1.05 if lit else 0.6)
        return Image.composite(Image.new("RGB", (size, size), tip), Image.new("RGB", (size, size), root), grad)

    rgb = Image.composite(half_fill(a_lit), half_fill(not a_lit), mask_a)
    layer = rgb.convert("RGBA")
    d = ImageDraw.Draw(layer)

    # Veins, then the midrib (tapering).
    for k in range(1, 8):
        i = int(len(rib) * (0.1 + k * 0.1))
        if i >= len(rib) - 2:
            break
        px, py = rib[i]
        for side in (1, -1):
            reach = width * 0.5 * (1 - abs(k - 3) * 0.09)
            # Veins sweep forward from the midrib, curving toward the edge.
            mx = px + (math.cos(a) * 0.35 + nx * side * 0.5) * reach
            my = py + (math.sin(a) * 0.35 + ny * side * 0.5) * reach
            ex = px + (math.cos(a) * 0.8 + nx * side * 0.8) * reach
            ey = py + (math.sin(a) * 0.8 + ny * side * 0.8) * reach
            d.line((px, py, mx, my, ex, ey), fill=scale(base, 1.6, 42), width=max(1, int(width * 0.016)), joint="curve")
    n = len(rib) - 1
    for i in range(n):
        w = max(1, int(width * 0.05 * (1 - i / n) + 1))
        d.line((rib[i], rib[i + 1]), fill=scale(base, 1.9, 200), width=w)

    # Specular streak on the lit half, close to the midrib.
    sheen = Image.new("L", (size, size), 0)
    off = width * 0.1 * (1 if a_lit else -1)
    s_poly, s_poly2, _ = leaf_halves(cx + nx * off, cy + ny * off, length * 0.7, width * 0.2, angle, bend)
    ImageDraw.Draw(sheen).polygon(s_poly + s_poly2, fill=170)
    sheen = sheen.filter(ImageFilter.GaussianBlur(width * 0.035 + 1))
    sheen = ImageChops.multiply(sheen, ImageChops.multiply(full, grad.point(lambda v: 90 + v * 0.65)))
    layer = Image.composite(Image.new("RGBA", (size, size), (226, 246, 214, 255)), layer, sheen)

    # Dark rim.
    ImageDraw.Draw(layer).line(poly_a + poly_b[:1], fill=scale(base, 0.45, 150), width=max(1, SS))
    layer.putalpha(full)
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return layer, (size, size)


def paste_leaf(canvas, x, y, length, width, angle, base, rng, blur=0.0, dim=1.0, shadow=True):
    img, (size, _) = leaf(length, width, angle, base, rng, blur=blur, dim=dim)
    pos = (int(x - size / 2), int(y - size / 2))
    if shadow and not blur:
        sh = Image.new("RGBA", img.size, (0, 12, 6, 0))
        sh.putalpha(img.getchannel("A").point(lambda v: v * 0.55))
        sh = sh.filter(ImageFilter.GaussianBlur(length * 0.05))
        _composite_clip(canvas, sh, (pos[0] + int(length * 0.03), pos[1] + int(length * 0.05)))
    _composite_clip(canvas, img, pos)


def _composite_clip(canvas, img, pos):
    """alpha_composite that tolerates negative or overflowing offsets."""
    x, y = pos
    sx, sy = max(0, -x), max(0, -y)
    dx, dy = max(0, x), max(0, y)
    w = min(img.width - sx, canvas.width - dx)
    h = min(img.height - sy, canvas.height - dy)
    if w <= 0 or h <= 0:
        return
    canvas.alpha_composite(img.crop((sx, sy, sx + w, sy + h)), (dx, dy))


def draw_vine(canvas, cx, cy, radius, start, turns, width, direction=1):
    """A thin gold tendril: a tapering spiral with a soft glow."""
    pts = []
    count = 220
    for i in range(count):
        t = i / (count - 1)
        ang = math.radians(start) + direction * t * turns * 2 * math.pi
        r = radius * (1 - 0.82 * t) ** 1.1
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).line(pts, fill=(255, 210, 120, 90), width=int(width * 3))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(width * 1.4)))
    d = ImageDraw.Draw(canvas)
    for i in range(count - 1):
        w = max(1, int(width * (1 - 0.6 * i / count)))
        d.line((pts[i], pts[i + 1]), fill=(196, 150, 62, 255), width=w)
    for i in range(0, count - 1, 2):
        w = max(1, int(width * 0.45 * (1 - 0.6 * i / count)))
        d.line((pts[i], pts[i + 1]), fill=(255, 232, 160, 220), width=w)
    return pts


def draw_flower(canvas, cx, cy, r, rng, blur=0.0, petals=5):
    size = int(r * 3 + blur * 4)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2
    rot = rng.uniform(0, 360)
    for k in range(petals):
        a = math.radians(rot + k * 360 / petals)
        petal = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        pd = ImageDraw.Draw(petal)
        px, py = c + math.cos(a) * r * 0.52, c + math.sin(a) * r * 0.52
        pts = []
        for i in range(40):
            t = 2 * math.pi * i / 40
            ex, ey = math.cos(t) * r * 0.55, math.sin(t) * r * 0.4
            pts.append((px + ex * math.cos(a) - ey * math.sin(a), py + ex * math.sin(a) + ey * math.cos(a)))
        pd.polygon(pts, fill=(250, 244, 226, 255))
        # Shade toward the centre, light at the petal tip.
        shade = Image.radial_gradient("L").resize((size, size))
        tint = Image.composite(Image.new("RGBA", (size, size), (226, 210, 170, 255)), petal, shade.point(lambda v: 255 - v).point(lambda v: max(0, v - 150) * 2))
        tint.putalpha(petal.getchannel("A"))
        ImageDraw.Draw(tint).line(pts + pts[:1], fill=(206, 188, 146, 160), width=max(1, SS))
        layer.alpha_composite(tint)
    d = ImageDraw.Draw(layer)
    d.ellipse((c - r * 0.24, c - r * 0.24, c + r * 0.24, c + r * 0.24), fill=(222, 170, 58, 255))
    for k in range(9):
        a = math.radians(k * 40 + rot)
        sx, sy = c + math.cos(a) * r * 0.14, c + math.sin(a) * r * 0.14
        d.ellipse((sx - r * 0.035, sy - r * 0.035, sx + r * 0.035, sy + r * 0.035), fill=(150, 98, 30, 255))
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    _composite_clip(canvas, layer, (int(cx - c), int(cy - c)))


def cluster(w, h, origin, direction, seed, leaves=22, spread=70, reach=0.75, flowers=(), vines=(), size=1.0):
    """Leaves fanning out from `origin` towards `direction` (degrees).

    `flowers` and `vines` are positions as (angle offset, distance) pairs,
    distance as a fraction of the cluster reach.
    """
    rng = random.Random(seed)
    W, H = w * SS, h * SS
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ox, oy = origin[0] * SS, origin[1] * SS
    span = math.hypot(W, H) * reach

    def place(angle_off, dist):
        ang = math.radians(direction + angle_off)
        return ox + math.cos(ang) * dist * span, oy + math.sin(ang) * dist * span

    # Back layer: big, dark, out of focus.
    for _ in range(leaves // 3):
        ang = direction + rng.uniform(-spread, spread)
        x, y = place(ang - direction, rng.uniform(0.05, 0.35))
        length = rng.uniform(0.4, 0.55) * span * size
        paste_leaf(canvas, x, y, length, length * rng.uniform(0.4, 0.48), ang + rng.uniform(-15, 15),
                   rng.choice(GREENS), rng, blur=7 * SS, dim=0.62)
    # Mid and front layers: crisp, glossy.
    front = leaves - leaves // 3
    for i in range(front):
        ang = direction + rng.uniform(-spread, spread) * (0.9 if i % 2 else 1)
        x, y = place(ang - direction, rng.uniform(0.0, 0.3) * (1 if i < front * 0.6 else 0.6))
        length = rng.uniform(0.32, 0.46) * span * size * (0.85 if i > front * 0.6 else 1)
        paste_leaf(canvas, x, y, length, length * rng.uniform(0.4, 0.47), ang + rng.uniform(-12, 12),
                   rng.choice(GREENS), rng, dim=0.92 if i < front // 2 else 1.0)
    # Thin gold tendrils curling over the leaves.
    for angle_off, dist, radius in vines:
        vx, vy = place(angle_off, dist)
        draw_vine(canvas, vx, vy, radius * span, rng.uniform(0, 360), 1.35, 1.8 * SS, rng.choice((-1, 1)))
    for angle_off, dist, radius, blurred in flowers:
        fx, fy = place(angle_off, dist)
        draw_flower(canvas, fx, fy, radius * span, rng, blur=3 * SS if blurred else 0)
    fade_far_edges(canvas, origin_left=ox < W / 2, origin_top=oy < H / 2)
    return canvas.resize((w, h), Image.LANCZOS)


def fade_far_edges(canvas, origin_left, origin_top, band=0.14):
    """Fades leaves out toward the edges away from the cluster's corner, so
    no leaf ends in a hard cut where the image ends."""
    W, H = canvas.size
    ramp = Image.linear_gradient("L")  # 0 at the top, 255 at the bottom

    def fade(v):
        return min(255, int(v / band))

    vertical = ramp.resize((W, H))
    if origin_top:
        vertical = ImageChops.invert(vertical)
    horizontal = ramp.rotate(90).resize((W, H))  # 0 at the left, 255 at the right
    if origin_left:
        horizontal = ImageChops.invert(horizontal)
    alpha = canvas.getchannel("A")
    alpha = ImageChops.multiply(alpha, vertical.point(fade))
    alpha = ImageChops.multiply(alpha, horizontal.point(fade))
    canvas.putalpha(alpha)


def sprig(w, h, seed):
    """A loose stem of small leaves for the right edge."""
    rng = random.Random(seed)
    W, H = w * SS, h * SS
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # Stem curving in from the right edge.
    stem = [(W * (1.02 - 0.75 * t) + math.sin(t * 3.0) * W * 0.06, H * (0.5 + 0.38 * (t - 0.5)) + math.sin(t * 2.2) * H * 0.06)
            for t in (i / 60 for i in range(61))]
    d = ImageDraw.Draw(canvas)
    d.line(stem, fill=(24, 70, 40, 255), width=3 * SS)
    for i, k in enumerate(range(6, 61, 9)):
        x, y = stem[k]
        size = (0.42 - i * 0.035) * W
        side = 1 if i % 2 else -1
        ang = 180 + side * rng.uniform(30, 50)
        blur = 4 * SS if i in (1, 4) else 0
        paste_leaf(canvas, x, y, size, size * 0.4, ang, rng.choice(GREENS), rng, blur=blur, dim=0.7 if blur else 1.0)
    paste_leaf(canvas, *stem[-1], 0.2 * W, 0.08 * W, 180, GREENS[1], rng)
    draw_vine(canvas, W * 0.55, H * 0.3, W * 0.16, 30, 1.3, 1.8 * SS, -1)
    return canvas.resize((w, h), Image.LANCZOS)


def main():
    out = ROOT / "assets/decor"
    out.mkdir(parents=True, exist_ok=True)
    layers = {
        "foliage_top_left": cluster(
            760, 820, (0, 0), 52, seed=11, leaves=24, spread=58, reach=0.95,
            flowers=[(-46, 0.3, 0.055, False), (30, 0.4, 0.055, False), (-12, 0.2, 0.045, False)],
            vines=[(30, 0.42, 0.08), (-40, 0.5, 0.06)]),
        "foliage_bottom_left": cluster(
            760, 760, (0, 760), -48, seed=23, leaves=24, spread=56, reach=0.95,
            flowers=[(26, 0.34, 0.05, False)],
            vines=[(-30, 0.44, 0.07), (40, 0.5, 0.05)]),
        "foliage_bottom_right": cluster(
            800, 800, (800, 800), -128, seed=37, leaves=26, spread=56, reach=0.95,
            flowers=[(-30, 0.3, 0.045, True), (24, 0.42, 0.04, False)],
            vines=[(30, 0.45, 0.07), (-36, 0.5, 0.05)]),
        "foliage_right": sprig(320, 520, seed=51),
    }
    for name, image in layers.items():
        path = out / f"{name}.webp"
        image.save(path, "WEBP", quality=86, method=6, exact=True)
        print(f"{path.relative_to(ROOT)}  {image.size}  {path.stat().st_size // 1024} KB")
    # Review sheet on the emerald felt colour, roughly as placed on a phone.
    sheet = Image.new("RGBA", (900, 1000), (14, 74, 47, 255))
    sheet.alpha_composite(layers["foliage_top_left"].resize((380, 410)), (0, 0))
    sheet.alpha_composite(layers["foliage_bottom_left"].resize((380, 380)), (0, 620))
    sheet.alpha_composite(layers["foliage_bottom_right"].resize((400, 400)), (500, 600))
    sheet.alpha_composite(layers["foliage_right"].resize((160, 260)), (740, 260))
    (ROOT / "art/review").mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(ROOT / "art/review/foliage-sheet.png")


if __name__ == "__main__":
    main()
