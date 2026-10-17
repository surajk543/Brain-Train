#!/usr/bin/env python3
"""Framed marketing screenshots for the stores, from the raw captures.

Each raw capture (test/visual/store_screenshots_test.dart) is boosted a
little, framed with rounded corners, a fine gold rim and a soft shadow, and
set on the game's night look (emerald gradient, gold glow, foliage from
assets/decor/ and assets/lobby/, fireflies) under a serif headline.

    python3 tool/store/make_store_shots.py            # every target
    python3 tool/store/make_store_shots.py ipad-13    # one target

Reads   art/store/phone/0N-*.png            (Google Play phone, 1080 x 1920)
        art/store/ios/iphone-6.9/0N-*.png   (1320 x 2868)
        art/store/ios/ipad-13/0N-*.png      (2064 x 2752)
Writes  art/store/styled/<target>/0N-*.png  (same sizes, RGB; JPEG q92 if a
        PNG would be over 8 MB)

Needs Pillow only. The headline font is the serif the app shows (Noto Serif;
Georgia on macOS), else DejaVu Serif or Liberation Serif.
"""

from __future__ import annotations

import math
import random
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/store/styled"
MAX_BYTES = 8_000_000

# Captions: (headline, subline) per shot, in shot order.
CAPTIONS = {
    "01": ("Relax with Mahjong tiles", "A calm garden of puzzles, day or night"),
    "02": ("Tap tiles into your tray", "Two of a kind clear together"),
    "03": ("Match fast for big combos", "Stuck? Hint, Undo and Shuffle help"),
    "04": ("675 levels to master", "From relaxed 1/10 to fiendish 10/10"),
    "05": ("Tray full? Revive and go on", "Plan ahead, keep your tray clear"),
    "06": ("Replay and beat your best", "Best time, score and combo saved"),
}

# Brand colours (lib/app/brand.dart, lib/app/theme.dart).
GOLD_LIGHT = (243, 220, 152)
GOLD = (216, 178, 94)
GOLD_WARM = (242, 201, 107)
GOLD_DEEP = (142, 108, 42)
IVORY = (240, 232, 212)
EMERALD_TOP = (13, 70, 53)
EMERALD = (11, 61, 46)
TEAL_NAVY = (4, 20, 32)

HEADLINE_FONTS = [
    "/usr/share/fonts/truetype/noto/NotoSerifDisplay-Bold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSerif-Bold.ttf",
    "/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
    "/Library/Fonts/Georgia Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
]
SUBLINE_FONTS = [
    "/usr/share/fonts/truetype/noto/NotoSerif-Italic.ttf",
    "/usr/share/fonts/truetype/noto/NotoSerif-Regular.ttf",
    "/System/Library/Fonts/Supplemental/Georgia Italic.ttf",
    "/Library/Fonts/Georgia Italic.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Italic.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf",
]


@dataclass(frozen=True)
class Target:
    name: str
    source: Path
    size: tuple[int, int]
    screen_width: float  # share of the image width
    headline: float  # headline font size, share of the image width
    top: float  # headline band, share of the image height
    bottom: float  # margin under the screen, share of the image height


TARGETS = [
    Target("play-phone", ROOT / "art/store/phone", (1080, 1920), 0.80, 0.083, 0.205, 0.026),
    Target("iphone-6.9", ROOT / "art/store/ios/iphone-6.9", (1320, 2868), 0.80, 0.083, 0.19, 0.026),
    Target("ipad-13", ROOT / "art/store/ios/ipad-13", (2064, 2752), 0.73, 0.062, 0.205, 0.04),
]


def font_path(candidates: list[str]) -> str:
    for path in candidates:
        if Path(path).exists():
            return path
    raise SystemExit(f"no serif font found (tried {', '.join(candidates)})")


# --- drawing helpers -------------------------------------------------------


def vertical_gradient(size: tuple[int, int], stops: list[tuple[float, tuple[int, int, int]]]) -> Image.Image:
    """A top-to-bottom gradient through colour [stops] (position 0..1, rgb)."""
    w, h = size
    column = Image.new("RGB", (1, h))
    px = column.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                k = (t - t0) / max(1e-9, t1 - t0)
                k = k * k * (3 - 2 * k)  # smoothstep
                px[0, y] = tuple(round(a + (b - a) * k) for a, b in zip(c0, c1))
                break
    return column.resize((w, h), Image.Resampling.NEAREST)


def soft_glow(size: tuple[int, int], center: tuple[float, float], radius: tuple[float, float], color, alpha: int) -> Image.Image:
    """An RGBA layer with a soft elliptical glow (drawn small, blurred, scaled up)."""
    w, h = size
    s = 8
    small = Image.new("L", (w // s, h // s), 0)
    cx, cy = center[0] / s, center[1] / s
    rx, ry = radius[0] / s, radius[1] / s
    ImageDraw.Draw(small).ellipse((cx - rx * 0.55, cy - ry * 0.55, cx + rx * 0.55, cy + ry * 0.55), fill=alpha)
    small = small.filter(ImageFilter.GaussianBlur(max(rx, ry) * 0.45))
    mask = small.resize((w, h), Image.Resampling.BICUBIC)
    layer = Image.new("RGBA", (w, h), color + (0,))
    layer.putalpha(mask)
    return layer


def halo(size: tuple[int, int], box: tuple[int, int, int, int], radius: float, spread: float, color, alpha: int) -> Image.Image:
    """A soft glow just around [box] (rim light behind the screen)."""
    w, h = size
    s = 4
    small = Image.new("L", (w // s, h // s), 0)
    l, t, r, b = (v / s for v in box)
    grow = spread * 0.35 / s
    ImageDraw.Draw(small).rounded_rectangle((l - grow, t - grow, r + grow, b + grow), radius=radius / s + grow, fill=alpha)
    mask = small.filter(ImageFilter.GaussianBlur(spread / s)).resize((w, h), Image.Resampling.BICUBIC)
    layer = Image.new("RGBA", (w, h), color + (0,))
    layer.putalpha(mask)
    return layer


def vignette(size: tuple[int, int], alpha: int) -> Image.Image:
    """Black towards the edges and corners, clear in the middle."""
    w, h = size
    s = 8
    small = Image.new("L", (w // s, h // s), alpha)
    ImageDraw.Draw(small).ellipse((-w / s * 0.1, h / s * 0.05, w / s * 1.1, h / s * 0.95), fill=0)
    mask = small.filter(ImageFilter.GaussianBlur(w / s * 0.22)).resize((w, h), Image.Resampling.BICUBIC)
    layer = Image.new("RGBA", (w, h), (0, 6, 6, 0))
    layer.putalpha(mask)
    return layer


def fireflies(size: tuple[int, int], keep_out: list[tuple[int, int, int, int]], rng: random.Random) -> Image.Image:
    """Soft bokeh dots and a few bright fireflies, off the screen and the text."""
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    soft = Image.new("RGBA", size, (0, 0, 0, 0))
    d_soft, d = ImageDraw.Draw(soft), ImageDraw.Draw(layer)
    unit = w / 1080
    placed = 0
    while placed < 22:
        x, y = rng.uniform(0, w), rng.uniform(h * 0.04, h * 0.98)
        if any(l - 20 * unit < x < r + 20 * unit and t - 20 * unit < y < b + 20 * unit for l, t, r, b in keep_out):
            continue
        placed += 1
        if placed % 3 == 0:
            rad = rng.uniform(16, 34) * unit  # out-of-focus bokeh disc
            col = rng.choice([GOLD_WARM, (150, 210, 160), GOLD_LIGHT])
            d_soft.ellipse((x - rad, y - rad, x + rad, y + rad), fill=col + (rng.randint(26, 46),))
        else:
            rad = rng.uniform(3, 6.5) * unit  # firefly: bright core in a halo
            d_soft.ellipse((x - rad * 4, y - rad * 4, x + rad * 4, y + rad * 4), fill=GOLD_WARM + (40,))
            d.ellipse((x - rad, y - rad, x + rad, y + rad), fill=(255, 240, 190, 225))
    soft = soft.filter(ImageFilter.GaussianBlur(9 * unit))
    layer = layer.filter(ImageFilter.GaussianBlur(1.6 * unit))
    return Image.alpha_composite(soft, layer)


def decor(path: str, width: float, *, mirror: bool = False, rotate: float = 0, alpha: float = 1.0, darken: float = 1.0) -> Image.Image:
    """A cut-out from the app's assets, scaled to [width] px."""
    im = Image.open(ROOT / path).convert("RGBA")
    if mirror:
        im = im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    im = im.resize((round(width), round(width * im.height / im.width)), Image.Resampling.LANCZOS)
    if rotate:
        im = im.rotate(rotate, resample=Image.Resampling.BICUBIC, expand=True)
    if darken != 1.0:
        rgb = ImageEnhance.Brightness(im.convert("RGB")).enhance(darken)
        rgb.putalpha(im.getchannel("A"))
        im = rgb
    if alpha != 1.0:
        im.putalpha(im.getchannel("A").point(lambda a: round(a * alpha)))
    return im


def leaf(index: int, width: float, rotate: float, blurred: bool = False) -> Image.Image:
    """One leaf of assets/lobby/leaf_sprites.webp (6 x 2 grid; row 2 blurred)."""
    sheet = Image.open(ROOT / "assets/lobby/leaf_sprites.webp").convert("RGBA")
    cw, ch = sheet.width // 6, sheet.height // 2
    row = 1 if blurred else 0
    im = sheet.crop((index * cw, row * ch, (index + 1) * cw, (row + 1) * ch))
    im = im.resize((round(width), round(width * ch / cw)), Image.Resampling.LANCZOS)
    return im.rotate(rotate, resample=Image.Resampling.BICUBIC, expand=True)


def paste(canvas: Image.Image, im: Image.Image, x: float, y: float) -> None:
    """Composites [im] at (x, y); parts off the top or left edge are cut."""
    x, y = round(x), round(y)
    crop = im.crop((max(0, -x), max(0, -y), im.width, im.height))
    canvas.alpha_composite(crop, (max(0, x), max(0, y)))


def rounded_mask(size: tuple[int, int], radius: float, scale: int = 4) -> Image.Image:
    """An antialiased rounded-rectangle mask."""
    w, h = size
    big = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), radius=radius * scale, fill=255)
    return big.resize((w, h), Image.Resampling.LANCZOS)


def boost(shot: Image.Image) -> Image.Image:
    """A little more colour and contrast, slightly crisper; the art stays itself."""
    shot = ImageEnhance.Color(shot).enhance(1.18)
    shot = ImageEnhance.Contrast(shot).enhance(1.06)
    return shot.filter(ImageFilter.UnsharpMask(radius=2, percent=55, threshold=3))


def framed(shot: Image.Image, width: int, unit: float) -> tuple[Image.Image, int]:
    """The boosted screen with rounded corners and a fine gold rim, plus its
    padding (the rim sits outside the screen)."""
    height = round(width * shot.height / shot.width)
    screen = boost(shot.convert("RGB")).resize((width, height), Image.Resampling.LANCZOS)
    radius = width * 0.045
    rim = max(2, round(3 * unit))
    pad = rim + 1
    out = Image.new("RGBA", (width + 2 * pad, height + 2 * pad), (0, 0, 0, 0))
    # Gold rim: a vertical gold gradient through a ring mask.
    ring_outer = rounded_mask(out.size, radius + pad)
    gold = vertical_gradient(out.size, [(0, GOLD_LIGHT), (0.45, GOLD), (1, GOLD_DEEP)]).convert("RGBA")
    gold.putalpha(ring_outer)
    out.alpha_composite(gold)
    # A hairline of dark between rim and screen keeps the edge crisp.
    inner = Image.new("RGBA", (width + 2, height + 2), (8, 22, 18, 255))
    inner.putalpha(rounded_mask(inner.size, radius + 1))
    out.alpha_composite(inner, (pad - 1, pad - 1))
    screen = screen.convert("RGBA")
    screen.putalpha(rounded_mask(screen.size, radius))
    out.alpha_composite(screen, (pad, pad))
    return out, pad


def shadow_of(framed_im: Image.Image, unit: float) -> Image.Image:
    alpha = framed_im.getchannel("A").point(lambda a: round(a * 0.78))
    blur = round(26 * unit)
    layer = Image.new("RGBA", (framed_im.width + 4 * blur, framed_im.height + 4 * blur), (0, 0, 0, 0))
    mask = Image.new("L", layer.size, 0)
    mask.paste(alpha, (2 * blur, 2 * blur))
    layer.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)))
    shade = Image.new("RGBA", layer.size, (2, 10, 8, 255))
    shade.putalpha(layer.getchannel("A"))
    return shade


# --- text ------------------------------------------------------------------


def text_width(font: ImageFont.FreeTypeFont, text: str) -> float:
    return font.getlength(text)


def wrap(font: ImageFont.FreeTypeFont, text: str, max_width: float) -> list[str]:
    """The most balanced two-line split (one line for one or two words), so
    every headline of a set has the same shape."""
    words = text.split()
    if len(words) < 3:
        return [text]
    best = None
    for i in range(1, len(words)):
        lines = [" ".join(words[:i]), " ".join(words[i:])]
        widest = max(text_width(font, l) for l in lines)
        if best is None or widest < best[0]:
            best = (widest, lines)
    return best[1]


def fits(font: ImageFont.FreeTypeFont, text: str, max_width: float) -> bool:
    return all(text_width(font, l) <= max_width for l in wrap(font, text, max_width))


def draw_headline(canvas: Image.Image, lines: list[str], font: ImageFont.FreeTypeFont, top: float, unit: float) -> float:
    """Gold-gradient serif lines centred from [top] with a soft dark shadow;
    returns the bottom."""
    w = canvas.width
    ascent, descent = font.getmetrics()
    line_h = (ascent + descent) * 1.02
    block_h = round(line_h * len(lines))
    mask = Image.new("L", (w, block_h + round(40 * unit)), 0)
    d = ImageDraw.Draw(mask)
    for i, line in enumerate(lines):
        d.text(((w - text_width(font, line)) / 2, i * line_h), line, font=font, fill=255)
    # Shadow: a soft dark halo and a tighter drop.
    for blur, offset, strength, color in [(18 * unit, 4 * unit, 0.85, (1, 12, 9)), (3 * unit, 3 * unit, 0.7, (20, 12, 0))]:
        sh = mask.filter(ImageFilter.GaussianBlur(blur)).point(lambda a: min(255, round(a * strength * 1.4)))
        layer = Image.new("RGBA", mask.size, color + (0,))
        layer.putalpha(sh)
        paste(canvas, layer, 0, top + offset)
    # Fill: light gold at the top of each line to warm gold below.
    fill = Image.new("RGB", mask.size)
    for i in range(len(lines)):
        band = vertical_gradient((w, round(line_h)), [(0, (255, 241, 196)), (0.42, GOLD_LIGHT), (0.75, GOLD_WARM), (1, GOLD)])
        fill.paste(band, (0, round(i * line_h)))
    fill = fill.convert("RGBA")
    fill.putalpha(mask)
    paste(canvas, fill, 0, top)
    return top + block_h


def draw_subline(canvas: Image.Image, text: str, font: ImageFont.FreeTypeFont, top: float, unit: float) -> float:
    w = canvas.width
    ascent, descent = font.getmetrics()
    mask = Image.new("L", (w, ascent + descent + round(20 * unit)), 0)
    ImageDraw.Draw(mask).text(((w - text_width(font, text)) / 2, 0), text, font=font, fill=255)
    sh = Image.new("RGBA", mask.size, (0, 10, 8, 0))
    sh.putalpha(mask.filter(ImageFilter.GaussianBlur(6 * unit)).point(lambda a: min(255, a * 2)))
    paste(canvas, sh, 0, top + 2 * unit)
    fill = Image.new("RGBA", mask.size, IVORY + (0,))
    fill.putalpha(mask.point(lambda a: round(a * 0.94)))
    paste(canvas, fill, 0, top)
    return top + ascent + descent


def divider(canvas: Image.Image, cx: float, y: float, half: float, unit: float) -> None:
    """A fine gold rule that fades out at both ends, with a small diamond."""
    w = round(half * 2)
    h = max(2, round(2 * unit))
    line = Image.new("RGBA", (w, h), GOLD + (0,))
    a = Image.new("L", (w, 1))
    for x in range(w):
        t = abs(x - w / 2) / (w / 2)
        a.putpixel((x, 0), round(200 * (1 - t) ** 1.5))
    line.putalpha(a.resize((w, h)))
    paste(canvas, line, cx - half, y)
    r = 5 * unit
    d = ImageDraw.Draw(canvas)
    d.polygon([(cx, y + h / 2 - r), (cx + r, y + h / 2), (cx, y + h / 2 + r), (cx - r, y + h / 2)], fill=GOLD_LIGHT + (235,))


# --- composition -----------------------------------------------------------


def compose(target: Target, shot_path: Path, headline: str, subline: str, head_font, sub_font) -> Image.Image:
    W, H = target.size
    unit = W / 1080
    rng = random.Random(f"{target.name}:{shot_path.stem}")

    canvas = vertical_gradient((W, H), [(0, EMERALD_TOP), (0.3, EMERALD), (0.7, (6, 34, 40)), (1, TEAL_NAVY)]).convert("RGBA")

    # The screen's place: centred under the headline band, a little margin below.
    shot = Image.open(shot_path)
    aspect = shot.height / shot.width
    band = H * target.top
    room = H - band - H * target.bottom
    sw = round(min(W * target.screen_width, room / aspect))
    sh = round(sw * aspect)
    sx = (W - sw) / 2
    sy = band + (room - sh)  # sits on the bottom margin
    keep_out = (round(sx), round(sy), round(sx + sw), round(sy + sh))

    # Light: darker edges, an emerald lift behind the title and a warm gold
    # halo around the screen.
    canvas.alpha_composite(vignette((W, H), 150))
    canvas.alpha_composite(soft_glow((W, H), (W / 2, band * 0.55), (W * 1.0, band * 1.3), (30, 120, 90), 55))
    canvas.alpha_composite(halo((W, H), keep_out, sw * 0.045, 40 * unit, GOLD_WARM, 125))

    # Foliage at the corners and edges, low-key, behind everything else.
    side = W - sx - sw  # one side margin
    foliage = [
        (decor("assets/lobby/night_foliage_tl.webp", W * 0.42, darken=0.8, alpha=0.9), -W * 0.07, -W * 0.08),
        (decor("assets/lobby/night_foliage_tr.webp", W * 0.40, darken=0.8, alpha=0.9), W * 0.69, -W * 0.09),
        (decor("assets/lobby/night_foliage_bl.webp", W * 0.46, darken=0.85), -W * 0.12, H - W * 0.36),
        (decor("assets/lobby/night_foliage_br.webp", W * 0.46, darken=0.85), W * 0.68, H - W * 0.36),
        (decor("assets/decor/foliage_bottom_right.webp", W * 0.38, alpha=0.95), W * 0.70, H - W * 0.31),
        (decor("assets/decor/foliage_top_left.webp", W * 0.34, alpha=0.95), -W * 0.06, -W * 0.07),
    ]
    for im, x, y in foliage:
        paste(canvas, im, x, y)
    # Lanterns hang in the side margins where they are wide enough (iPad).
    if side >= W * 0.12:
        lantern_w = side * 0.5
        paste(canvas, decor("assets/lobby/night_lantern.webp", lantern_w, alpha=0.95), (side - lantern_w) / 2, sy + sh * 0.02)
        paste(canvas, decor("assets/lobby/night_lantern.webp", lantern_w * 0.86, alpha=0.9), W - side / 2 - lantern_w * 0.43, sy + sh * 0.38)
    # Drifting leaves.
    for i, (lx, ly, lw, rot, blur) in enumerate(
        [
            (0.05, 0.52, 0.06, 35, False),
            (0.90, 0.30, 0.05, -50, False),
            (0.02, 0.78, 0.07, 70, True),
            (0.93, 0.70, 0.06, -20, True),
        ]
    ):
        paste(canvas, leaf((i * 2 + 1) % 6, W * lw, rot + rng.uniform(-10, 10), blur), W * lx, H * ly)
    text_box = (round(W * 0.06), 0, round(W * 0.94), round(sy))
    canvas.alpha_composite(fireflies((W, H), [keep_out, text_box], rng))

    # The screen, framed, on its shadow.
    frame, pad = framed(shot, sw, unit)
    shadow = shadow_of(frame, unit)
    blur = round(26 * unit)
    paste(canvas, shadow, sx - pad - 2 * blur, sy - pad - 2 * blur + 18 * unit)
    paste(canvas, frame, sx - pad, sy - pad)

    # Headline and subline, centred in the band.
    max_text = W * 0.86
    lines = wrap(head_font, headline, max_text)
    ascent, descent = head_font.getmetrics()
    head_h = (ascent + descent) * 1.02 * len(lines)
    s_ascent, s_descent = sub_font.getmetrics()
    gap = 16 * unit
    block = head_h + gap * 2 + 2 * unit + (s_ascent + s_descent)
    top = max(30 * unit, (sy - pad - block) / 2 - 6 * unit)
    bottom = draw_headline(canvas, lines, head_font, top, unit)
    divider(canvas, W / 2, bottom + gap * 0.6, min(W * 0.16, 180 * unit), unit)
    draw_subline(canvas, subline, sub_font, bottom + gap * 1.8, unit)

    return canvas.convert("RGB")


def common_font(target: Target, path: str, captions: list[str]) -> ImageFont.FreeTypeFont:
    """The largest size up to the target's that fits every caption in two lines."""
    W = target.size[0]
    size = round(W * target.headline)
    while size > 20:
        font = ImageFont.truetype(path, size)
        if all(fits(font, c, W * 0.86) and len(wrap(font, c, W * 0.86)) <= 2 for c in captions):
            return font
        size -= 2
    raise SystemExit("captions too long")


def save(im: Image.Image, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    png = path.with_suffix(".png")
    im.save(png, optimize=True)
    if png.stat().st_size <= MAX_BYTES:
        path.with_suffix(".jpg").unlink(missing_ok=True)
        return png
    png.unlink()
    jpg = path.with_suffix(".jpg")
    im.save(jpg, quality=92, optimize=True, subsampling=0)
    return jpg


def main(argv: list[str]) -> None:
    wanted = set(argv) or {t.name for t in TARGETS}
    head_path, sub_path = font_path(HEADLINE_FONTS), font_path(SUBLINE_FONTS)
    for target in TARGETS:
        if target.name not in wanted:
            continue
        head_font = common_font(target, head_path, [h for h, _ in CAPTIONS.values()])
        sub_font = ImageFont.truetype(sub_path, round(head_font.size * 0.46))
        for key, (headline, subline) in CAPTIONS.items():
            sources = sorted(target.source.glob(f"{key}-*.png"))
            if not sources:
                raise SystemExit(f"missing {target.source}/{key}-*.png")
            image = compose(target, sources[0], headline, subline, head_font, sub_font)
            assert image.size == target.size and image.mode == "RGB"
            written = save(image, OUT / target.name / sources[0].stem)
            print(f"{written.relative_to(ROOT)}  {image.size[0]}x{image.size[1]}  {written.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main(sys.argv[1:])
