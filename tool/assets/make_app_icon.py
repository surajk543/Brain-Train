#!/usr/bin/env python3
"""Generate the Brain Train app icon from the official logo.

Uses the round emblem of art/branding/brain-train-logo.jpg (brain, train and
track). The "Brain Train" name banner is left out: it would be unreadable at
launcher size. The logo's own white background fills the icon.

Usage: python3 tool/assets/make_app_icon.py [--logo path] [--emblem x0,y0,x1,y1]
Writes: art/app_icon/brain-train-icon-1024.png, Android mipmaps, iOS AppIcon set.
"""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
S = 1024


def build(logo_path: Path, emblem_box) -> Image.Image:
    logo = Image.open(logo_path).convert("RGB")
    emblem = logo.crop(emblem_box)
    # Fit the emblem into 80% of the icon, centred, on the logo's white.
    scale = 0.80 * S / max(emblem.size)
    emblem = emblem.resize((round(emblem.width * scale), round(emblem.height * scale)), Image.LANCZOS)
    icon = Image.new("RGB", (S, S), logo.getpixel((3, 3)))
    icon.paste(emblem, ((S - emblem.width) // 2, (S - emblem.height) // 2))
    return icon


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--logo", default=str(ROOT / "art/branding/brain-train-logo.jpg"))
    parser.add_argument("--emblem", default="237,201,788,686", help="crop box of the round emblem in the logo")
    args = parser.parse_args()
    icon = build(Path(args.logo), tuple(int(v) for v in args.emblem.split(",")))
    out = ROOT / "art/app_icon"
    out.mkdir(parents=True, exist_ok=True)
    icon.save(out / "brain-train-icon-1024.png")

    # Android legacy launcher icons: rounded square on transparency.
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), int(S * 0.22), fill=255)
    android = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    android.paste(icon, (0, 0), mask)
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        android.resize((px, px), Image.LANCZOS).save(ROOT / f"android/app/src/main/res/mipmap-{folder}/ic_launcher.png")

    # Android 8+ adaptive icon: white background layer + emblem foreground on
    # the 108dp canvas, kept inside the 66dp safe zone so masks never clip it.
    foreground = Image.new("RGB", (S, S), icon.getpixel((3, 3)))
    emblem_fg = icon.resize((round(S * 0.66 / 0.80),) * 2, Image.LANCZOS)
    foreground.paste(emblem_fg, ((S - emblem_fg.width) // 2, (S - emblem_fg.height) // 2))
    for folder, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
        foreground.resize((px, px), Image.LANCZOS).save(ROOT / f"android/app/src/main/res/mipmap-{folder}/ic_launcher_foreground.png")

    # iOS: full-bleed, no alpha (the system applies the mask).
    iconset = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for image in json.loads((iconset / "Contents.json").read_text())["images"]:
        px = round(float(image["size"].split("x")[0]) * int(image["scale"].rstrip("x")))
        icon.resize((px, px), Image.LANCZOS).save(iconset / image["filename"])
    print(f"icon written: {out / 'brain-train-icon-1024.png'}")


if __name__ == "__main__":
    main()
