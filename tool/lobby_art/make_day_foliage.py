#!/usr/bin/env python3
"""Day versions of the gameplay edge foliage (redesign 1.1.0).

The Night felt's foliage (assets/decor/foliage_*.webp, written by the art
pipeline's tool/assets/make_foliage.py) is repainted in daylight so the Day
gameplay screen reads as the sunlit garden of the Day lobby
(assets/lobby/day/, tool/lobby_art/make_day_lobby_art.py):

- leaf greens are gradient-mapped from their own shading onto the Day
  lobby's sunlit greens (fresh, slightly yellow), so veins, sheen and the
  out-of-focus leaves keep their shape;
- the edges facing the sun (top right) get a warm rim;
- the existing cream flowers and gold tendrils are kept, and a few more cream
  flowers (the Day lobby's own flower drawing) are added.

Writes assets/decor/day/foliage_{right,top_left,bottom_left,bottom_right}.webp
(same sizes and placement as the night files; FeltFoliage.day in
lib/app/theme.dart). Reads the night files fresh on every run.

Usage: python3 -I tool/lobby_art/make_day_foliage.py [--review DIR]
--review writes a contact sheet of night vs day on the Day felt to DIR.
"""

import importlib.util
import random
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/decor"
OUT = ROOT / "assets/decor/day"


def _day_art():
    """The Day lobby script, for its flower drawing and helpers."""
    spec = importlib.util.spec_from_file_location("make_day_lobby_art", Path(__file__).with_name("make_day_lobby_art.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ART = _day_art()
clamp, mix = ART.clamp, ART.mix

# Leaf shading (0 = darkest night shade, 1 = brightest highlight) mapped to
# the Day lobby's greens: shade greens, sunlit greens, warm highlight.
LEAF_RAMP = [
    (0.00, (30, 86, 48)),
    (0.22, (50, 116, 56)),
    (0.45, (82, 152, 64)),
    (0.70, (124, 182, 76)),
    (1.00, (226, 238, 168)),
]


def ramp(t):
    t = max(0.0, min(1.0, t))
    for (t0, c0), (t1, c1) in zip(LEAF_RAMP, LEAF_RAMP[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / (t1 - t0))
    return LEAF_RAMP[-1][1]


# One lookup per luminance step (0..255).
RAMP_LUT = [ramp((v / 255) / 0.62) for v in range(256)]


def recolour(img):
    """Gradient-maps leaf pixels onto sunlit greens; flowers (cream, low
    saturation), their orange centres and the gold tendrils (red >= green)
    keep their colours."""
    rgba = img.convert("RGBA")
    r, g, b, a = rgba.split()
    src = list(zip(r.tobytes(), g.tobytes(), b.tobytes()))
    out = []
    for rr, gg, bb in src:
        # How leaf-like a pixel is: green clearly above red (cream petals,
        # orange centres and gold tendrils have red >= green) and above blue.
        if gg <= bb:
            leaf = 0.0
        else:
            leaf = max(0.0, min(1.0, ((gg - rr) / max(gg, 1) - 0.06) / 0.12))
        if leaf <= 0:
            out.append((rr, gg, bb))
            continue
        lum = int(0.3 * rr + 0.59 * gg + 0.11 * bb)
        day = RAMP_LUT[lum]
        out.append(mix((rr, gg, bb), day, leaf))
    rgb = Image.new("RGB", rgba.size)
    rgb.putdata(out)
    result = rgb.convert("RGBA")
    result.putalpha(a)
    return result


def sun_rim(img, strength=0.55, reach=5):
    """A warm rim on the edges facing the sun (up and to the right): where the
    alpha ends towards the top right, screen in a pale gold."""
    a = img.getchannel("A")
    shifted = ImageChops.offset(a, -reach, reach)  # alpha seen from the top right
    rim = ImageChops.subtract(a, shifted).filter(ImageFilter.GaussianBlur(reach * 0.6))
    rim = ImageChops.multiply(rim, a).point(lambda v: clamp(v * strength))
    rgb = ART.screen_light(img.convert("RGB"), rim, ART.SUN_RIM)
    lit = rgb.convert("RGBA")
    lit.putalpha(a)
    return lit


def add_flowers(img, flowers, seed):
    """flowers: (x fraction, y fraction, radius fraction of the width, blur px)."""
    rnd = random.Random(seed)
    w = img.width
    for fx, fy, rf, blur in flowers:
        fl = ART.flower_layer(rf * w, rot=rnd.uniform(0, 72), blur=blur)
        ART.composite_at(img, fl, fx * img.width - fl.width / 2, fy * img.height - fl.height / 2)
    return img


# Per file: extra cream flowers (placed on the leaf masses, clear of the
# night art's own flowers) and the RNG seed for their rotation.
FILES = {
    "foliage_top_left.webp": ([(0.30, 0.12, 0.05, 0), (0.20, 0.50, 0.035, 0.8), (0.36, 0.30, 0.038, 1.2)], 211),
    "foliage_right.webp": ([(0.84, 0.38, 0.07, 0), (0.30, 0.78, 0.07, 0.8)], 223),
    "foliage_bottom_left.webp": ([(0.18, 0.62, 0.045, 0), (0.30, 0.40, 0.04, 0.8), (0.10, 0.88, 0.05, 1.0)], 227),
    "foliage_bottom_right.webp": ([(0.80, 0.52, 0.042, 0), (0.55, 0.62, 0.04, 0.6), (0.90, 0.80, 0.046, 1.0)], 229),
}


def save(img, name):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    img.save(path, "WEBP", quality=84, method=6, alpha_quality=90)
    print(f"{path.relative_to(ROOT)}  {img.size}  {path.stat().st_size} bytes")
    return img


def review(pairs, out_dir):
    """Night and Day foliage side by side, on the Day felt."""
    h = 320
    tiles = []
    for night, day in pairs:
        for im in (night, day):
            tiles.append(im.resize((max(1, int(im.width * h / im.height)), h), Image.LANCZOS))
    sheet = Image.new("RGBA", (sum(t.width for t in tiles) + 12 * len(tiles), h), (40, 112, 66, 255))
    x = 0
    for t in tiles:
        sheet.alpha_composite(t, (x, 0))
        x += t.width + 12
    out_dir.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(out_dir / "gameplay-day-foliage.png")


def main():
    pairs = []
    for name, (flowers, seed) in FILES.items():
        night = Image.open(SRC / name).convert("RGBA")
        day = add_flowers(sun_rim(recolour(night)), flowers, seed)
        pairs.append((night, save(day, name)))
    if "--review" in sys.argv:
        review(pairs, Path(sys.argv[sys.argv.index("--review") + 1]))


if __name__ == "__main__":
    main()
