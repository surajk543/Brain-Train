#!/usr/bin/env python3
"""Generate the Tile Park app icons, store icon and logo screen image from the official logo.

The logo (art/branding/tile-park-logo.png) is a purple-framed board of tiles on white. Icons crop it to the
frame and fill everything outside the frame's rounded corners with the frame's purple, so no white shows
whatever mask the platform applies. Android 8+ gets the board on a purple background layer, inside the mask.

Usage: python3 tool/branding/make_tile_park_icons.py [--logo path] [--preview dir]
Writes: art/app_icon/tile-park-icon-1024.png, art/store/icon-512.png (Play), Android mipmaps + adaptive
background colour, iOS AppIcon set, assets/branding/tile_park_logo.jpg (logo screen).
"""

import argparse
import json
import re
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
S = 1024
# The frame's outer rim; also the Android adaptive background.
PURPLE = (116, 50, 244)
# Corner radius of the frame, as a fraction of its width (measured on the logo).
FRAME_RADIUS = 0.178
# Share of the 108dp adaptive canvas the board takes (the circle mask shows 72dp).
ADAPTIVE_BOARD = 0.56


def rounded_mask(size: int, radius: float, inset: float) -> Image.Image:
    """Anti-aliased rounded square mask (drawn at 4x)."""
    k = 4
    big = Image.new("L", (size * k, size * k), 0)
    i = inset * k
    ImageDraw.Draw(big).rounded_rectangle((i, i, size * k - 1 - i, size * k - 1 - i), radius * k, fill=255)
    return big.resize((size, size), Image.LANCZOS)


def frame_crop(logo: Image.Image) -> Image.Image:
    """The logo cropped to its purple frame, as a square (the frame is very nearly square)."""
    r, g, b = logo.split()
    purple = ImageChops.subtract(b, g).point(lambda v: 255 if v > 110 else 0)
    x0, y0, x1, y1 = purple.getbbox()
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    box = tuple(round(v) for v in (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2))
    square = Image.new("RGB", (side, side), PURPLE)
    square.paste(logo.crop(box), (0, 0))
    return square


def build(logo_path: Path):
    logo = Image.open(logo_path).convert("RGB")
    board = frame_crop(logo).resize((S, S), Image.LANCZOS)
    # Inset 3 px so the white anti-aliasing around the frame never shows.
    mask = rounded_mask(S, FRAME_RADIUS * S, inset=3)
    full = Image.new("RGB", (S, S), PURPLE)
    full.paste(board, (0, 0), mask)
    cutout = board.convert("RGBA")
    cutout.putalpha(mask)
    return logo, full, cutout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--logo", default=str(ROOT / "art/branding/tile-park-logo.png"))
    parser.add_argument("--preview", help="also write mask previews (circle, squircle, iOS) to this folder")
    args = parser.parse_args()
    logo, full, cutout = build(Path(args.logo))

    out = ROOT / "art/app_icon"
    out.mkdir(parents=True, exist_ok=True)
    full.save(out / "tile-park-icon-1024.png")
    # Google Play store icon: 512 x 512, full square (Play rounds it).
    full.resize((512, 512), Image.LANCZOS).save(ROOT / "art/store/icon-512.png")

    # Android legacy launcher icons: rounded square on transparency.
    legacy = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    legacy.paste(full, (0, 0), rounded_mask(S, 0.22 * S, inset=0))
    res = ROOT / "android/app/src/main/res"
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        legacy.resize((px, px), Image.LANCZOS).save(res / f"mipmap-{folder}/ic_launcher.png")

    # Android 8+ adaptive icon: purple background layer + the framed board, centred on the 108dp canvas.
    foreground = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fg_board = cutout.resize((round(S * ADAPTIVE_BOARD),) * 2, Image.LANCZOS)
    foreground.alpha_composite(fg_board, ((S - fg_board.width) // 2, (S - fg_board.height) // 2))
    for folder, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
        foreground.resize((px, px), Image.LANCZOS).save(res / f"mipmap-{folder}/ic_launcher_foreground.png")
    colors = res / "values/colors.xml"
    hex_purple = "#{:02X}{:02X}{:02X}".format(*PURPLE)
    colors.write_text(
        re.sub(r'(<color name="ic_launcher_background">)#[0-9A-Fa-f]{6}(</color>)', rf"\g<1>{hex_purple}\2",
               colors.read_text())
    )

    # iOS: full-bleed, no alpha (the system applies the mask).
    iconset = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for image in json.loads((iconset / "Contents.json").read_text())["images"]:
        px = round(float(image["size"].split("x")[0]) * int(image["scale"].rstrip("x")))
        full.resize((px, px), Image.LANCZOS).save(iconset / image["filename"])

    # Logo screen (after the studio intro): the whole logo on its own white.
    logo.resize((720, 720), Image.LANCZOS).save(ROOT / "assets/branding/tile_park_logo.jpg", quality=90)

    if args.preview:
        preview = Path(args.preview)
        preview.mkdir(parents=True, exist_ok=True)
        bg = Image.new("RGBA", (S, S), PURPLE + (255,))
        adaptive = Image.alpha_composite(bg, foreground)
        visible = adaptive.crop((S // 6, S // 6, S - S // 6, S - S // 6)).resize((S, S), Image.LANCZOS)
        circle = Image.new("L", (S, S), 0)
        ImageDraw.Draw(circle).ellipse((0, 0, S - 1, S - 1), fill=255)
        for name, img, m in (
            ("android-circle", visible, circle),
            ("android-squircle", visible, rounded_mask(S, 0.30 * S, 0)),
            ("ios", full, rounded_mask(S, 0.2237 * S, 0)),
        ):
            shown = Image.new("RGB", (S, S), (255, 255, 255))
            shown.paste(img.convert("RGB"), (0, 0), m)
            shown.resize((256, 256), Image.LANCZOS).save(preview / f"{name}.png")
    print(f"icon written: {out / 'tile-park-icon-1024.png'}")


if __name__ == "__main__":
    main()
